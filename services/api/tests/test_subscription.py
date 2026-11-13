import base64
import json
from datetime import UTC, datetime
from urllib.parse import parse_qs, urlsplit
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from nebula_api import subscription
from nebula_api.account.service import AccountEntry
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.auth.user_service import (
    AuthenticatedUser,
    AuthenticationRejected,
    DeviceLimitReached,
)
from nebula_api.devices.schemas import XrayClientResponse
from nebula_api.provisioning.service import ProvisioningRejected
from nebula_api.servers.service import AvailableProfileEntry, AvailableServerEntry
from nebula_api.settings import Settings
from nebula_api.subscription import share_link

_ID = UUID("11111111-2222-3333-4444-555555555555")


def _credential(**fields: object) -> XrayClientResponse:
    base: dict[str, object] = {
        "client_id": _ID,
        "uuid": _ID,
        "server_address": "de.example.org",
        "port": 443,
        "sni": "de.example.org",
        "transport": "raw",
        "transport_security": "tls",
    }
    return XrayClientResponse.model_validate(base | fields)


def test_vless_reality_link() -> None:
    link = share_link(
        _credential(
            transport_security="reality",
            reality_public_key="PBK",
            reality_short_id="ab",
            flow="xtls-rprx-vision",
        ),
        "germany | VLESS REALITY",
    )
    assert link is not None
    parts = urlsplit(link)
    assert parts.scheme == "vless" and parts.username == str(_ID) and parts.port == 443
    query = {k: v[0] for k, v in parse_qs(parts.query).items()}
    assert query["security"] == "reality" and query["pbk"] == "PBK" and query["sid"] == "ab"
    assert query["type"] == "tcp" and query["flow"] == "xtls-rprx-vision"
    assert query["encryption"] == "none"
    assert parts.fragment == "germany%20%7C%20VLESS%20REALITY"


def test_websocket_and_grpc_carry_their_settings() -> None:
    ws = share_link(_credential(transport="websocket", path="/ws"), "x")
    assert ws is not None and "type=ws" in ws and "path=%2Fws" in ws and "host=de.example.org" in ws
    grpc = share_link(_credential(transport="grpc", service_name="svc"), "x")
    assert grpc is not None and "serviceName=svc" in grpc and "mode=gun" in grpc


def test_vmess_link_is_base64_json() -> None:
    link = share_link(
        _credential(protocol="vmess", transport="websocket", transport_security="none", path="/v"),
        "germany | VMess",
    )
    assert link is not None and link.startswith("vmess://")
    data = json.loads(base64.b64decode(link.removeprefix("vmess://")))
    assert data["id"] == str(_ID) and data["net"] == "ws" and data["path"] == "/v"
    assert data["tls"] == "" and data["ps"] == "germany | VMess"


def test_shadowsocks_and_hysteria() -> None:
    ss = share_link(
        _credential(protocol="shadowsocks", method="2022-blake3-aes-128-gcm", password="pw"),  # noqa: S106 - test fixture
        "ss",
    )
    assert ss is not None
    user = urlsplit(ss).username or ""
    assert base64.urlsafe_b64decode(user + "==").decode() == "2022-blake3-aes-128-gcm:pw"
    hy = share_link(
        _credential(transport="hysteria", obfs_password="ob", port_hop="20000-30000"),  # noqa: S106
        "hy",
    )
    assert hy is not None and hy.startswith(f"hysteria2://{_ID}@de.example.org:443/?")
    assert "obfs=salamander" in hy and "obfs-password=ob" in hy and "mport=20000-30000" in hy


def test_ipv6_host_is_bracketed() -> None:
    link = share_link(_credential(server_address="2a01:4f8::1"), "x")
    assert link is not None and "@[2a01:4f8::1]:443" in link


# The two routes, with stand-in services.

_USER = UUID("11111111-1111-4111-8111-111111111111")
_DEVICE = UUID("33333333-3333-4333-8333-333333333333")
_SECRET = "s" * 43


class _Auth:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    async def authenticate_access_token(self, _token: str) -> AuthenticatedUser:
        return AuthenticatedUser(user_id=_USER, session_id=_ID, device_id=_ID)

    async def new_subscription(self, **_: object) -> str:
        if self.error is not None:
            raise self.error
        return _SECRET

    async def subscription_owner(self, secret: str) -> tuple[UUID, UUID] | None:
        return (_USER, _DEVICE) if secret == _SECRET else None


class _Accounts:
    def __init__(self, entry: AccountEntry | None) -> None:
        self.entry = entry

    async def get_account(self, _user_id: UUID) -> AccountEntry | None:
        return self.entry


class _Servers:
    async def list_available_servers(
        self, _user_id: UUID, *, include_maintenance: bool
    ) -> list[AvailableServerEntry]:
        def profile(code: str, protocol: str = "vless") -> AvailableProfileEntry:
            return AvailableProfileEntry(
                code=code,
                display_name=code,
                protocol_id=_ID,
                protocol_code=protocol,
                ad_block=False,
            )

        return [
            AvailableServerEntry(
                code="germany",
                display_name="germany",
                public_host="de.example.org",
                profiles=[
                    profile("vless-reality"),
                    profile("wg", "wireguard"),
                    profile("vless-enc-dns"),
                    profile("broken"),
                ],
            )
        ]


def _account(expires_at: datetime | None = None) -> AccountEntry:
    return AccountEntry(
        email="owner@example.org",
        username="parsa",
        state="active",
        device_limit=5,
        devices_in_use=2,
        expires_at=expires_at,
        used_bytes=300,
        lifetime_bytes=900,
        quota_bytes=1000,
        remaining_bytes=700,
    )


def _client(auth: _Auth | None = None, account: AccountEntry | None = None) -> TestClient:
    settings = Settings(env="test")
    app = FastAPI()
    app.state.settings = settings
    app.state.user_auth_service = auth or _Auth()
    app.state.account_service = _Accounts(account)
    app.state.server_discovery_service = _Servers()
    install_auth_http_safeguards(app, settings)
    app.include_router(subscription.router)
    return TestClient(app)


def test_new_link_is_a_path() -> None:
    answer = _client().post("/v1/account/subscription", headers={"Authorization": "Bearer t"})
    assert answer.status_code == 200
    assert answer.json() == {"path": f"/v1/sub/{_SECRET}"}


def test_new_link_names_the_cdn_when_there_is_one() -> None:
    # Other apps fetch it from networks that block the server's own address.
    client = _client()
    client.app.state.settings = Settings(env="test", cdn_host="cdn.example.org")  # type: ignore[attr-defined]
    answer = client.post("/v1/account/subscription", headers={"Authorization": "Bearer t"})
    assert answer.json()["url"] == f"https://cdn.example.org/v1/sub/{_SECRET}"


@pytest.mark.parametrize(
    ("error", "code"), [(DeviceLimitReached(), 403), (AuthenticationRejected(), 403)]
)
def test_new_link_refusals(error: Exception, code: int) -> None:
    answer = _client(_Auth(error)).post(
        "/v1/account/subscription", headers={"Authorization": "Bearer t"}
    )
    assert answer.status_code == code


def test_unknown_link_and_gone_account_are_404() -> None:
    assert _client(account=_account()).get("/v1/sub/nope").status_code == 404
    assert _client(account=None).get(f"/v1/sub/{_SECRET}").status_code == 404


def test_link_lists_share_links_with_usage(monkeypatch: pytest.MonkeyPatch) -> None:
    asked: list[str] = []

    async def credential(_request: object, **kwargs: str) -> XrayClientResponse:
        asked.append(kwargs["protocol_profile_code"])
        if kwargs["protocol_profile_code"] == "broken":
            raise ProvisioningRejected()
        return _credential(transport_security="reality", reality_public_key="K")

    monkeypatch.setattr(subscription, "xray_client_for", credential)
    subscription._cache.clear()
    client = _client(account=_account(datetime(2027, 1, 1, tzinfo=UTC)))
    answer = client.get(f"/v1/sub/{_SECRET}")
    assert answer.status_code == 200
    links = base64.b64decode(answer.text).decode().splitlines()
    assert len(links) == 1 and links[0].startswith("vless://")
    # WireGuard and the DNS tunnel are not asked for at all.
    assert asked == ["vless-reality", "broken"]
    assert answer.headers["subscription-userinfo"] == (
        "upload=0; download=300; total=1000; expire=1798761600"
    )
    # Cached: a second fetch provisions nothing.
    assert client.get(f"/v1/sub/{_SECRET}").text == answer.text
    assert asked == ["vless-reality", "broken"]


def test_missing_service_is_503() -> None:
    app = FastAPI()
    app.include_router(subscription.router)
    assert TestClient(app).get(f"/v1/sub/{_SECRET}").status_code == 503


def test_unknown_protocol_has_no_link() -> None:
    assert share_link(_credential(protocol="wireguard"), "x") is None
    trojan = share_link(_credential(protocol="trojan", password="pw"), "x")  # noqa: S106
    assert trojan is not None and trojan.startswith("trojan://pw@") and "encryption" not in trojan
