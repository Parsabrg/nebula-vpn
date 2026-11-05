"""The DNS tunnel's details for signed-in apps (plan 10)."""

from pathlib import Path
from typing import cast

from fastapi import FastAPI
from fastapi.testclient import TestClient
from test_servers_routes import AUTH_HEADERS, FakeUserAuthService

from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.auth.user_service import UserAuthService
from nebula_api.dns_tunnel import router
from nebula_api.settings import Settings


def _client(**settings: object) -> TestClient:
    app = FastAPI()
    app.state.settings = Settings(env="test", **settings)  # type: ignore[arg-type]
    app.state.user_auth_service = cast(UserAuthService, FakeUserAuthService())
    install_auth_http_safeguards(app, app.state.settings)
    app.include_router(router)
    return TestClient(app)


def test_signed_in_apps_get_the_name_key_and_server(tmp_path: Path) -> None:
    key = tmp_path / "cottendns_key"
    key.write_text("0123456789abcdef0123456789abcdef\n")
    with _client(
        dns_tunnel_domain="t.example.org",
        dns_tunnel_server="de-1",
        dns_tunnel_key_file=str(key),
    ) as client:
        response = client.get("/v1/dns-tunnel/", headers=AUTH_HEADERS)

    assert response.status_code == 200
    assert response.json() == {
        "domain": "t.example.org",
        "key": "0123456789abcdef0123456789abcdef",
        "encryption_method": 5,
        "server_code": "de-1",
    }
    assert response.headers["cache-control"] == "no-store"


def test_signed_out_is_refused(tmp_path: Path) -> None:
    with _client(dns_tunnel_domain="t.example.org", dns_tunnel_server="de-1") as client:
        assert client.get("/v1/dns-tunnel/").status_code == 401


def test_none_configured_or_no_key_is_404(tmp_path: Path) -> None:
    with _client() as client:
        assert client.get("/v1/dns-tunnel/", headers=AUTH_HEADERS).status_code == 404
    with _client(
        dns_tunnel_domain="t.example.org",
        dns_tunnel_server="de-1",
        dns_tunnel_key_file=str(tmp_path / "missing"),
    ) as client:
        assert client.get("/v1/dns-tunnel/", headers=AUTH_HEADERS).status_code == 404
