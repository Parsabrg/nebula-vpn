"""Relays in the admin panel: the list (settings and panel, with health) and
adding or removing the panel's own."""

import asyncio
import json
from typing import cast
from uuid import UUID

from fastapi import FastAPI
from fastapi.testclient import TestClient

from nebula_api.auth.admin_service import AdminAuthService, AdminPrincipal
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.models.types import AdminRole
from nebula_api.relays import Relay, RelayCatalog, RelayHealth
from nebula_api.settings import Settings
from nebula_api.topology_admin.relays_routes import router
from nebula_api.topology_admin.service import ProfilePort, TopologyAdminService

ADMIN_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
SESSION_ID = UUID("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
DE = UUID("11111111-1111-4111-8111-111111111111")
THR = UUID("22222222-2222-4222-8222-222222222222")
ORIGIN = "http://localhost:3000"
HEADERS = {"Origin": ORIGIN, "X-CSRF-Token": "v1.csrf-canary"}
SETTINGS_RELAY = {
    "code": "de-via-old",
    "display_name": "Germany via the old one",
    "exit": "de-1",
    "via": "thr",
    "host": "198.51.100.9",
    "ports": {"vless-tcp-tls": 2053},
}


class FakeAuth:
    def __init__(self, step_up: bool = True) -> None:
        self.step_up = step_up

    async def principal(self, _token: str) -> AdminPrincipal:
        return AdminPrincipal(ADMIN_ID, SESSION_ID, AdminRole.OWNER, self.step_up, "totp")

    async def validate_and_rotate_csrf(self, _s: str, _c: str) -> str:
        return "v1.csrf-replacement"


class FakeService:
    def __init__(self) -> None:
        self.added: list[dict[str, object]] = []
        self.removed: list[str] = []
        self.taken = False

    async def relay_context(
        self,
    ) -> tuple[dict[str, tuple[UUID, str, str]], dict[str, ProfilePort]]:
        return (
            {"de-1": (DE, "Germany", "203.0.113.4"), "thr": (THR, "Tehran", "198.51.100.7")},
            {
                "vless-tcp-tls": ProfilePort(port=8453, udp=False),
                "hysteria2": ProfilePort(8450, True),
            },
        )

    async def add_relay(self, **kwargs: object) -> None:
        if self.taken:
            raise ValueError("taken")
        self.added.append(kwargs)

    async def remove_relay(self, *, code: str, **_: object) -> bool:
        self.removed.append(code)
        return code == "de-1-via-thr"


class FakeCatalog(RelayCatalog):
    def __init__(self, relays: tuple[Relay, ...]) -> None:
        self._held = relays
        self.forgotten = 0

    def forget(self) -> None:
        self.forgotten += 1

    async def relays(self) -> tuple[Relay, ...]:
        return self._held


class FakeRedis:
    def __init__(self, up: set[str]) -> None:
        self.up = up

    async def mget(self, keys: list[str]) -> list[object]:
        return ["1" if key.rsplit(":", 1)[1] in self.up else None for key in keys]

    async def set(self, name: str, value: str, ex: int) -> object:
        return True


PANEL_RELAY = Relay(
    code="de-1-via-thr",
    display_name="Germany via Tehran",
    exit="de-1",
    via="thr",
    host="198.51.100.7",
    ports={"vless-tcp-tls": 443, "hysteria2": 443},
)


def client(
    service: FakeService, catalog: FakeCatalog | None = None, step_up: bool = True
) -> TestClient:
    settings = Settings(env="test", relays=json.dumps([SETTINGS_RELAY]))
    app = FastAPI()
    app.state.settings = settings
    app.state.admin_auth_service = cast(AdminAuthService, FakeAuth(step_up))
    app.state.topology_admin_service = cast(TopologyAdminService, service)
    app.state.relay_catalog = catalog
    app.state.relay_health = RelayHealth(FakeRedis({"de-1-via-thr"}))
    install_auth_http_safeguards(app, settings)
    app.include_router(router)
    test_client = TestClient(app)
    test_client.cookies.set(settings.admin_cookie_name, "v1.session-canary")
    test_client.cookies.set(settings.admin_csrf_cookie_name, "v1.csrf-canary")
    return test_client


def post(
    path: str,
    body: object,
    service: FakeService,
    catalog: FakeCatalog | None = None,
    step_up: bool = True,
) -> int:
    """One request per client: the CSRF token rotates after each change."""
    with client(service, catalog, step_up) as c:
        return c.post(path, json=body, headers=HEADERS).status_code


def test_the_list_holds_both_kinds_with_health_and_setup_details() -> None:
    with client(FakeService(), FakeCatalog((PANEL_RELAY,))) as c:
        body = c.get("/v1/admin/relays").json()
    items = body["items"]
    assert body["report_url"].startswith("http")
    assert [(i["code"], i["source"], i["up"]) for i in items] == [
        ("de-via-old", "settings", False),
        ("de-1-via-thr", "panel", True),
    ]
    panel = items[1]
    assert (panel["exit_name"], panel["exit_host"], panel["via_name"]) == (
        "Germany",
        "203.0.113.4",
        "Tehran",
    )
    assert panel["ports"] == [
        {"profile_code": "vless-tcp-tls", "port": 443, "exit_port": 8453, "udp": False},
        {"profile_code": "hysteria2", "port": 443, "exit_port": 8450, "udp": True},
    ]


def test_adding_names_it_from_its_servers_and_forgets_the_cache() -> None:
    service = FakeService()
    catalog = FakeCatalog(())
    body = {
        "display_name": " Germany via Tehran ",
        "exit_server_id": str(DE),
        "via_server_id": str(THR),
        "host": "198.51.100.7",
        "ports": {"vless-tcp-tls-adblock": 443, "hysteria2": 443},
    }
    with client(service, catalog) as c:
        answer = c.post("/v1/admin/relays", json=body, headers=HEADERS)
    assert answer.status_code == 204
    added = service.added[0]
    assert (added["code"], added["display_name"]) == ("de-1-via-thr", "Germany via Tehran")
    # An ad-block sibling shares its base profile's port.
    assert added["ports"] == {"vless-tcp-tls": 443, "hysteria2": 443}
    assert catalog.forgotten == 1


def test_adding_is_refused_without_step_up_or_with_bad_fields() -> None:
    body = {
        "display_name": "X",
        "exit_server_id": str(DE),
        "via_server_id": str(THR),
        "host": "198.51.100.7",
        "ports": {"vless-tcp-tls": 70000},
    }
    ok = {**body, "ports": {"vless-tcp-tls": 443}}
    assert post("/v1/admin/relays", ok, FakeService(), step_up=False) == 403
    assert post("/v1/admin/relays", body, FakeService()) == 422
    unknown = {**ok, "exit_server_id": str(ADMIN_ID)}
    assert post("/v1/admin/relays", unknown, FakeService()) == 404
    taken = FakeService()
    taken.taken = True
    assert post("/v1/admin/relays", ok, taken) == 409


def test_a_relay_already_listed_is_not_added_twice() -> None:
    body = {
        "display_name": "Again",
        "exit_server_id": str(DE),
        "via_server_id": str(THR),
        "host": "198.51.100.7",
        "ports": {"vless-tcp-tls": 443},
    }
    with client(FakeService(), FakeCatalog((PANEL_RELAY,))) as c:
        assert c.post("/v1/admin/relays", json=body, headers=HEADERS).status_code == 409


def test_removing_only_the_panels_own() -> None:
    service = FakeService()
    catalog = FakeCatalog((PANEL_RELAY,))
    codes = [
        post(f"/v1/admin/relays/{code}/delete", {}, service, catalog)
        for code in ("de-via-old", "nope", "de-1-via-thr")
    ]
    assert codes == [409, 404, 204]
    assert catalog.forgotten == 1


def test_no_service_is_503() -> None:
    app = FastAPI()
    settings = Settings(env="test")
    app.state.settings = settings
    app.state.admin_auth_service = cast(AdminAuthService, FakeAuth())
    install_auth_http_safeguards(app, settings)
    app.include_router(router)
    with TestClient(app) as c:
        c.cookies.set(settings.admin_cookie_name, "v1.session-canary")
        assert c.get("/v1/admin/relays").status_code == 503


def test_the_catalog_reads_the_database_at_most_every_few_seconds() -> None:
    reads: list[int] = []

    class Session:
        async def __aenter__(self) -> "Session":
            return self

        async def __aexit__(self, *_: object) -> None:
            return None

    async def fake_load(_session: object) -> tuple[Relay, ...]:
        reads.append(1)
        return (PANEL_RELAY,)

    import nebula_api.relays as relays_module

    original = relays_module.load_panel_relays
    relays_module.load_panel_relays = fake_load  # type: ignore[assignment]
    try:
        catalog = RelayCatalog(cast(object, Session))  # type: ignore[arg-type]
        assert asyncio.run(catalog.relays()) == (PANEL_RELAY,)
        asyncio.run(catalog.relays())
        assert len(reads) == 1
        catalog.forget()
        asyncio.run(catalog.relays())
        assert len(reads) == 2
    finally:
        relays_module.load_panel_relays = original
