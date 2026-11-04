"""Relays: a server listed on its own that forwards to another (the exit).

The relay hands out the device's credential on the exit, at the relay's
address and port; it is offered only while its agent last reached the exit.
"""

import asyncio
import json
from dataclasses import replace
from typing import cast
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError
from test_devices_routes import (
    AUTH_HEADERS,
    DEVICE_ID,
    FakeProvisioningService,
    FakeUserAuthService,
)
from test_servers_routes import FakeServerDiscoveryService

from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.auth.user_service import UserAuthService
from nebula_api.devices.routes import router as devices_router
from nebula_api.provisioning.service import ProvisioningService, RequestXrayClientResult
from nebula_api.relays import RELAY_UP_SECONDS, RelayHealth, parse_relays, with_relay_codes
from nebula_api.servers.routes import router as servers_router
from nebula_api.servers.service import (
    AvailableProfileEntry,
    AvailableServerEntry,
    ServerDiscoveryService,
)
from nebula_api.settings import Settings
from nebula_api.usage.poll import UsagePollSummary

RELAY = {
    "code": "de-via-thr",
    "display_name": "Germany via Tehran",
    "exit": "de-1",
    "via": "thr",
    "host": "198.51.100.7",
    "ports": {"vless-tcp-tls": 443, "hysteria2": 443},
}
RELAYS = json.dumps([RELAY])


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, tuple[str, int]] = {}

    async def mget(self, keys: list[str]) -> list[object]:
        return [self.values.get(key, (None,))[0] for key in keys]

    async def set(self, name: str, value: str, ex: int) -> object:
        self.values[name] = (value, ex)
        return True

    async def delete(self, *names: str) -> object:
        for name in names:
            self.values.pop(name, None)
        return 1


class RecordingProvisioning(FakeProvisioningService):
    def __init__(self) -> None:
        super().__init__()
        self.server_codes: list[object] = []

    async def request_xray_client(self, **kwargs: object) -> RequestXrayClientResult:
        self.server_codes.append(kwargs["server_code"])
        return await super().request_xray_client(**kwargs)

    async def revoke_xray_client(self, **kwargs: object):  # type: ignore[no-untyped-def]
        self.server_codes.append(kwargs["server_code"])
        return await super().revoke_xray_client(**kwargs)


def _health(*, up: bool) -> RelayHealth:
    health = RelayHealth(FakeRedis())
    if up:
        asyncio.run(health.record(parse_relays(RELAYS), {"thr"}))
    return health


def _app(health: RelayHealth | None) -> FastAPI:
    settings = Settings(env="test", relays=RELAYS)
    app = FastAPI()
    app.state.settings = settings
    app.state.user_auth_service = cast(UserAuthService, FakeUserAuthService())
    app.state.relay_health = health
    install_auth_http_safeguards(app, settings)
    return app


def _profile(code: str, protocol: str, port: int | None = None) -> AvailableProfileEntry:
    return AvailableProfileEntry(
        code=code,
        display_name=code,
        protocol_id=uuid4(),
        protocol_code=protocol,
        ad_block=code.endswith("-adblock"),
        required_port=port,
        transport="tcp",
    )


def _servers(health: RelayHealth | None, *, include_maintenance: bool = False) -> list[dict]:  # type: ignore[type-arg]
    discovery = FakeServerDiscoveryService()
    discovery.entries = [
        AvailableServerEntry(
            code="de-1",
            display_name="Germany",
            public_host="de.example.test",
            profiles=[
                _profile("vless-tcp-tls", "vless", 8447),
                _profile("vless-tcp-tls-adblock", "vless", 8447),
                _profile("vless-ws-tls", "vless", 8448),
                _profile("wireguard-native", "wireguard", 51820),
            ],
        )
    ]
    app = _app(health)
    app.state.server_discovery_service = cast(ServerDiscoveryService, discovery)
    app.include_router(servers_router)
    with TestClient(app) as client:
        response = client.get(
            "/v1/servers/",
            params={"include_maintenance": include_maintenance},
            headers=AUTH_HEADERS,
        )
    assert response.status_code == 200
    return response.json()["items"]  # type: ignore[no-any-return]


def test_relay_is_listed_with_the_exits_forwarded_profiles_at_its_ports() -> None:
    items = _servers(_health(up=True))

    assert [item["code"] for item in items] == ["de-1", "de-via-thr"]
    relay = items[1]
    assert (relay["display_name"], relay["public_host"], relay["maintenance"]) == (
        "Germany via Tehran",
        "198.51.100.7",
        False,
    )
    # Only what is forwarded; the ad-block sibling shares its port.
    assert [(p["code"], p["required_port"]) for p in relay["profiles"]] == [
        ("vless-tcp-tls", 443),
        ("vless-tcp-tls-adblock", 443),
    ]


@pytest.mark.parametrize("health", [None, _health(up=False)])
def test_a_relay_not_known_to_reach_its_exit_is_shown_as_maintenance(
    health: RelayHealth | None,
) -> None:
    assert [item["code"] for item in _servers(health)] == ["de-1"]
    relay = _servers(health, include_maintenance=True)[1]
    assert relay["maintenance"] is True


def _devices(provisioning: RecordingProvisioning, health: RelayHealth | None) -> TestClient:
    app = _app(health)
    app.state.provisioning_service = cast(ProvisioningService, provisioning)
    app.include_router(devices_router)
    return TestClient(app)


def test_relay_hands_out_the_exits_credential_at_its_own_address() -> None:
    provisioning = RecordingProvisioning()
    provisioning.xray_request_result = replace(
        provisioning.xray_request_result, port_hop="20000-50000"
    )
    body = {"server_code": "de-via-thr", "protocol_profile_code": "vless-tcp-tls-adblock"}
    with _devices(provisioning, _health(up=True)) as client:
        response = client.post(
            f"/v1/devices/{DEVICE_ID}/xray-client", json=body, headers=AUTH_HEADERS
        )
        revoked = client.post(
            f"/v1/devices/{DEVICE_ID}/xray-client/revoke", json=body, headers=AUTH_HEADERS
        )

    assert response.status_code == 200
    got = response.json()
    assert (got["server_address"], got["port"], got["port_hop"]) == ("198.51.100.7", 443, None)
    # TLS still names the exit, whose certificate the app checks.
    assert got["sni"] == "vps1.example.com"
    # One credential: asked for and revoked on the exit itself.
    assert revoked.status_code == 204
    assert provisioning.server_codes == ["de-1", "de-1"]


def test_relay_refuses_what_it_does_not_forward_and_while_down() -> None:
    provisioning = RecordingProvisioning()
    with _devices(provisioning, _health(up=True)) as client:
        missing = client.post(
            f"/v1/devices/{DEVICE_ID}/xray-client",
            json={"server_code": "de-via-thr", "protocol_profile_code": "vless-ws-tls"},
            headers=AUTH_HEADERS,
        )
    with _devices(provisioning, _health(up=False)) as client:
        down = client.post(
            f"/v1/devices/{DEVICE_ID}/xray-client",
            json={"server_code": "de-via-thr", "protocol_profile_code": "vless-tcp-tls"},
            headers=AUTH_HEADERS,
        )

    assert (missing.status_code, down.status_code) == (404, 423)
    assert provisioning.server_codes == []


def test_health_follows_the_relays_own_check() -> None:
    redis = FakeRedis()
    health = RelayHealth(redis)
    relays = parse_relays(RELAYS)
    summary = UsagePollSummary(
        servers_polled=2,
        servers_failed=0,
        samples=0,
        credentials_active=0,
        sources_failed=[],
        relay_checked={"thr"},
    )

    asyncio.run(health.record(relays, summary.relay_checked))
    assert asyncio.run(health.up(relays)) == {"de-via-thr"}
    assert redis.values["nebula:relay-up:de-via-thr"][1] == RELAY_UP_SECONDS
    asyncio.run(health.record(relays, set()))
    assert asyncio.run(health.up(relays)) == set()
    assert asyncio.run(health.up(())) == set()


@pytest.mark.parametrize(
    "change",
    [
        {"code": "de-1"},
        {"ports": {"vless-tcp-tls": 0}},
        {"ports": {"vless-tcp-tls-adblock": 443}},
        {"ports": {}},
        {"host": "bad host"},
        {"extra": 1},
    ],
)
def test_bad_relay_settings_are_refused(change: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        Settings(env="test", relays=json.dumps([{**RELAY, **change}]))


def test_relay_codes_are_unique_and_empty_means_none() -> None:
    with pytest.raises(ValidationError, match="unique"):
        Settings(env="test", relays=json.dumps([RELAY, RELAY]))
    assert Settings(env="test").relay_list() == ()


def test_a_device_on_the_exit_also_holds_its_relays() -> None:
    # The app ends a tunnel whose server is missing from its device's codes;
    # without this, a relay tunnel dropped with "access ended" (phone, 2026-11-04).
    relays = parse_relays(RELAYS)
    assert with_relay_codes(["de-1", "thr"], relays) == ["de-1", "de-via-thr", "thr"]
    assert with_relay_codes(["thr"], relays) == ["thr"]
