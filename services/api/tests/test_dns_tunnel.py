"""DNS tunnels (plan 10): what signed-in apps get, and the admin panel's
routes that set a server's names, show its DNS records and check them."""

from typing import cast
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from test_relays_admin import HEADERS, FakeAuth
from test_servers_routes import AUTH_HEADERS, FakeUserAuthService

import nebula_api.topology_admin.dns_tunnel_routes as routes
from nebula_api.auth.admin_service import AdminAuthService
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.auth.user_service import UserAuthService
from nebula_api.dns_tunnel import router
from nebula_api.dns_tunnels import Check, TunnelEntry, clean_names, records
from nebula_api.settings import Settings

KEY = "0123456789abcdef0123456789abcdef"  # gitleaks:allow (test value)
DE = UUID("11111111-1111-4111-8111-111111111111")
NL = UUID("33333333-3333-4333-8333-333333333333")
TUNNELS = [
    TunnelEntry(DE, "de-1", "de.example.org", ["nt.example.org", "t.backup.eu"], KEY),
    TunnelEntry(NL, "nl", "203.0.113.20", ["t2.example.org"], "f" * 32),
]


def _app_client(tunnels: list[TunnelEntry]) -> TestClient:
    app = FastAPI()
    app.state.settings = Settings(env="test")
    app.state.user_auth_service = cast(UserAuthService, FakeUserAuthService())

    async def source() -> list[TunnelEntry]:
        return tunnels

    app.state.dns_tunnel_source = source
    install_auth_http_safeguards(app, app.state.settings)
    app.include_router(router)
    return TestClient(app)


def test_signed_in_apps_get_every_tunnel_and_the_first_for_older_apps() -> None:
    with _app_client(TUNNELS) as client:
        response = client.get("/v1/dns-tunnel/", headers=AUTH_HEADERS)

    assert response.status_code == 200
    body = response.json()
    first = {
        "domains": ["nt.example.org", "t.backup.eu"],
        "key": KEY,
        "encryption_method": 5,
        "server_code": "de-1",
    }
    assert {k: body[k] for k in first} == first
    assert body["tunnels"] == [
        first,
        {
            "domains": ["t2.example.org"],
            "key": "f" * 32,
            "encryption_method": 5,
            "server_code": "nl",
        },
    ]
    assert response.headers["cache-control"] == "no-store"


def test_signed_out_is_refused_and_none_is_404() -> None:
    with _app_client(TUNNELS) as client:
        assert client.get("/v1/dns-tunnel/").status_code == 401
    with _app_client([]) as client:
        assert client.get("/v1/dns-tunnel/", headers=AUTH_HEADERS).status_code == 404


def test_names_are_cleaned_and_checked() -> None:
    assert clean_names([" NT.Example.org. ", "", "nt.example.org", "t.b.eu"]) == [
        "nt.example.org",
        "t.b.eu",
    ]
    for bad in (
        ["not a name"],
        ["example"],
        ["a.example.org"] * 1 + [f"n{i}.e.org" for i in range(4)],
    ):
        with pytest.raises(ValueError):
            clean_names(bad)


def test_records_put_the_nameserver_beside_the_name() -> None:
    assert records("t2.example.org", "203.0.113.20") == [
        ("t2.example.org", "NS", "ns-t2.example.org"),
        ("ns-t2.example.org", "A", "203.0.113.20"),
    ]


class Calls:
    def __init__(self) -> None:
        self.set: list[dict[str, object]] = []
        self.pushed: list[UUID] = []


@pytest.fixture
def calls(monkeypatch: pytest.MonkeyPatch) -> Calls:
    seen = Calls()

    async def list_tunnels(_sessions: object) -> list[TunnelEntry]:
        return TUNNELS

    async def set_tunnel(_sessions: object, **kwargs: object) -> TunnelEntry | None:
        seen.set.append(kwargs)
        if kwargs["server_id"] not in (DE, NL):
            return None
        return TunnelEntry(
            cast(UUID, kwargs["server_id"]),
            "nl",
            "203.0.113.20",
            cast(list[str], kwargs["domains"]),
            "f" * 32,
        )

    async def push(_sessions: object, _agents: object, server_id: UUID) -> bool:
        seen.pushed.append(server_id)
        return True

    async def check(name: str, public_host: str) -> tuple[str | None, list[Check]]:
        return "203.0.113.20", [Check("delegated", True, name), Check("answers", False, "no")]

    for name, fake in (
        ("list_tunnels", list_tunnels),
        ("set_tunnel", set_tunnel),
        ("push", push),
        ("check", check),
    ):
        monkeypatch.setattr(routes, name, fake)
    return seen


def _admin(step_up: bool = True) -> TestClient:
    settings = Settings(env="test")
    app = FastAPI()
    app.state.settings = settings
    app.state.admin_auth_service = cast(AdminAuthService, FakeAuth(step_up))
    app.state.dns_tunnel_sessions = object()
    app.state.dns_tunnel_agents = object()
    install_auth_http_safeguards(app, settings)
    app.include_router(routes.router)
    client = TestClient(app)
    client.cookies.set(settings.admin_cookie_name, "v1.session-canary")
    client.cookies.set(settings.admin_csrf_cookie_name, "v1.csrf-canary")
    return client


def test_setting_a_server_s_names_saves_and_pushes(calls: Calls) -> None:
    with _admin() as client:
        response = client.post(
            f"/v1/admin/dns-tunnels/{NL}", json={"domains": ["T3.example.org"]}, headers=HEADERS
        )
    assert response.status_code == 200
    assert response.json()["domains"] == ["t3.example.org"]
    assert response.json()["applied"] is True
    assert calls.set[0]["domains"] == ["t3.example.org"]
    assert calls.pushed == [NL]


@pytest.mark.parametrize(
    ("body", "code"),
    [
        ({"domains": ["not a name"]}, 422),
        ({"domains": ["nt.example.org"]}, 409),  # already Germany's
    ],
)
def test_bad_names_are_refused(calls: Calls, body: object, code: int) -> None:
    with _admin() as client:
        response = client.post(f"/v1/admin/dns-tunnels/{NL}", json=body, headers=HEADERS)
    assert response.status_code == code
    assert calls.set == []


def test_a_change_needs_step_up(calls: Calls) -> None:
    with _admin(step_up=False) as client:
        response = client.post(
            f"/v1/admin/dns-tunnels/{NL}", json={"domains": ["t3.example.org"]}, headers=HEADERS
        )
    assert response.status_code == 403
    assert calls.set == []


def test_the_list_and_the_check(calls: Calls) -> None:
    with _admin() as client:
        listed = client.get("/v1/admin/dns-tunnels").json()
        checked = client.get(f"/v1/admin/dns-tunnels/{NL}/check").json()
        missing = client.get("/v1/admin/dns-tunnels/44444444-4444-4444-8444-444444444444/check")
    assert [item["server_code"] for item in listed["items"]] == ["de-1", "nl"]
    assert "key" not in listed["items"][0]
    assert checked["server_ip"] == "203.0.113.20"
    assert checked["records"] == [
        {"name": "t2.example.org", "type": "NS", "value": "ns-t2.example.org"},
        {"name": "ns-t2.example.org", "type": "A", "value": "203.0.113.20"},
    ]
    assert [c["ok"] for c in checked["checks"]] == [True, False]
    assert missing.status_code == 404
