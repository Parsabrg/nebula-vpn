"""Two panel routes: the address subscription links name, and the one-time
token for adding a server."""

import json
from datetime import UTC, datetime
from typing import cast
from uuid import UUID, uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient

from nebula_api.auth.admin_service import AdminAuthService, AdminPrincipal
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.enrollment.routes import admin_router as enrollment_router
from nebula_api.enrollment.service import EnrollmentService, LabelInUse, MintedToken
from nebula_api.models.types import AdminRole
from nebula_api.settings import Settings
from nebula_api.subscription import AUTOMATIC, SUBSCRIPTION_HOST
from nebula_api.topology_admin.service import ProfilePort, TopologyAdminService
from nebula_api.topology_admin.subscription_link_routes import router as link_router

ADMIN_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
THR = UUID("22222222-2222-4222-8222-222222222222")
HEADERS = {"Origin": "http://localhost:3000", "X-CSRF-Token": "v1.csrf-canary"}
RELAY = {
    "code": "de-via-thr",
    "display_name": "Germany via Tehran",
    "exit": "de-1",
    "via": "thr",
    "host": "198.51.100.7",
    "ports": {"vless-tcp-tls": 2053},
}


class FakeAuth:
    async def principal(self, _token: str) -> AdminPrincipal:
        return AdminPrincipal(ADMIN_ID, uuid4(), AdminRole.OWNER, True, "totp")

    async def validate_and_rotate_csrf(self, _s: str, _c: str) -> str:
        return "v1.csrf-replacement"


class FakeTopology:
    def __init__(self, chosen: str | None = None) -> None:
        self.chosen = chosen
        self.chosen_now: list[tuple[str, str]] = []

    async def choice(self, key: str) -> str | None:
        return self.chosen if key == SUBSCRIPTION_HOST else None

    async def choose(self, *, key: str, value: str, admin_id: UUID, request_id: UUID) -> None:
        self.chosen_now.append((key, value))

    async def relay_context(
        self,
    ) -> tuple[dict[str, tuple[UUID, str, str]], dict[str, ProfilePort]]:
        return {"thr": (THR, "Tehran", "198.51.100.7")}, {}


class FakeEnrollment:
    def __init__(self, taken: bool = False) -> None:
        self.taken = taken

    async def mint(self, *, label: str, **_: object) -> MintedToken:
        if self.taken:
            raise LabelInUse(label)
        return MintedToken(
            token=uuid4().hex, token_id=uuid4(), label=label, expires_at=datetime.now(UTC)
        )


def client(
    topology: FakeTopology | None = None, enrollment: FakeEnrollment | None = None
) -> TestClient:
    settings = Settings(
        env="test",
        relays=json.dumps([RELAY]),
        cdn_host="cdn.example.org, ",
        api_public_url="https://api.example.org",
    )
    app = FastAPI()
    app.state.settings = settings
    app.state.admin_auth_service = cast(AdminAuthService, FakeAuth())
    if topology is not None:
        app.state.topology_admin_service = cast(TopologyAdminService, topology)
    if enrollment is not None:
        app.state.enrollment_service = cast(EnrollmentService, enrollment)
    install_auth_http_safeguards(app, settings)
    app.include_router(link_router)
    app.include_router(enrollment_router)
    test_client = TestClient(app)
    test_client.cookies.set(settings.admin_cookie_name, "v1.session-canary")
    test_client.cookies.set(settings.admin_csrf_cookie_name, "v1.csrf-canary")
    return test_client


def test_the_offered_link_addresses_and_the_choice() -> None:
    with client(FakeTopology("cdn.example.org")) as c:
        body = c.get("/v1/admin/subscription-link").json()
    assert body["choice"] == "cdn.example.org"
    assert [o["value"] for o in body["options"]] == [
        AUTOMATIC,
        "cdn.example.org",
        "198.51.100.7:8445",
        "api.example.org",
    ]


def test_a_choice_no_longer_offered_reads_as_automatic() -> None:
    with client(FakeTopology("gone.example.org")) as c:
        assert c.get("/v1/admin/subscription-link").json()["choice"] == AUTOMATIC


def test_choosing_takes_only_an_offered_address() -> None:
    topology = FakeTopology()
    with client(topology) as c:
        assert (
            c.post(
                "/v1/admin/subscription-link", json={"choice": "evil.example"}, headers=HEADERS
            ).status_code
            == 422
        )
    with client(topology) as c:
        assert (
            c.post(
                "/v1/admin/subscription-link", json={"choice": "cdn.example.org"}, headers=HEADERS
            ).status_code
            == 204
        )
    assert topology.chosen_now == [(SUBSCRIPTION_HOST, "cdn.example.org")]


def test_no_topology_service_is_503() -> None:
    with client() as c:
        assert c.get("/v1/admin/subscription-link").status_code == 503


def test_a_join_token_names_this_server_and_refuses_a_taken_name() -> None:
    with client(enrollment=FakeEnrollment()) as c:
        response = c.post(
            "/v1/admin/nodes/enrollment-tokens", json={"label": "node-02"}, headers=HEADERS
        )
    assert response.status_code == 200
    assert (response.json()["label"], response.json()["api_url"]) == (
        "node-02",
        "https://api.example.org",
    )
    with client(enrollment=FakeEnrollment(taken=True)) as c:
        assert (
            c.post(
                "/v1/admin/nodes/enrollment-tokens", json={"label": "node-02"}, headers=HEADERS
            ).status_code
            == 409
        )
