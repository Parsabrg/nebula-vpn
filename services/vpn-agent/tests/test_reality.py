"""VLESS + REALITY: Vision on raw TCP and XHTTP, no domain or certificate.

A probe without the key gets the borrowed site's TLS handshake; a client
with it gets VLESS. Served on two public ports, users changed live.
"""

import asyncio
import json
from pathlib import Path, PurePosixPath

import pytest
from pydantic import ValidationError
from test_drivers_xray import _provision_request
from test_drivers_xray_live import FakeXray

import nebula_agent.drivers.xray as xray
from nebula_agent.drivers.xray import NativeXrayDriver
from nebula_agent.drivers.xray_config_store import XrayConfigStore, client_email
from nebula_agent.settings import Settings

_PRIVATE = "reality-private-key-canary"
_PUBLIC = "reality-public-key-canary"


def _settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "env": "test",
        "xray_reality_enabled": True,
        "xray_reality_private_key": _PRIVATE,
        "xray_reality_public_key": _PUBLIC,
        "xray_reality_short_id": "0123abcd",
        "xray_reality_dest": "www.example.com:443",
        "xray_reality_server_name": "www.example.com",
        "xray_live_client_updates": True,
        "xray_api_host": "127.25.41.4",
    }
    values.update(overrides)
    return Settings(**values)  # type: ignore[arg-type]


def _setup(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> NativeXrayDriver:
    store = XrayConfigStore(
        PurePosixPath(str(tmp_path / "state")), PurePosixPath(str(tmp_path / "config"))
    )
    driver = NativeXrayDriver(_settings(), store)
    monkeypatch.setattr(xray, "run_fixed_argv", FakeXray(driver))
    monkeypatch.setattr(xray, "_LINGER_POLL_SECONDS", 0.0)
    return driver


def _inbound(driver: NativeXrayDriver, tag: str) -> dict[str, object]:
    served = json.loads(driver._config_store.xray_config_path.read_text())
    return next(i for i in served["inbounds"] if i["tag"] == tag)


@pytest.mark.parametrize(
    "overrides",
    [{"xray_reality_private_key": None}, {"xray_reality_public_key": None}],
)
def test_reality_needs_its_key_pair(overrides: dict[str, object]) -> None:
    with pytest.raises(ValidationError, match="xray_reality"):
        _settings(**overrides)


def test_short_id_is_hex_and_ports_are_their_own() -> None:
    with pytest.raises(ValidationError):
        _settings(xray_reality_short_id="not-hex!")
    with pytest.raises(ValidationError, match="distinct"):
        _settings(xray_reality_xhttp_port=8456)


def test_off_by_default() -> None:
    codes = {p.protocol_profile_code for p in Settings(env="test").build_xray_inbound_profiles()}
    assert not {c for c in codes if "reality" in c}


def test_vision_is_served_with_the_borrowed_name(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    driver = _setup(tmp_path, monkeypatch)
    request = _provision_request(protocol_profile_code="vless-reality-vision")

    response = asyncio.run(driver.provision_client(request))

    assert response.state == "active"
    assert (response.port, response.transport, response.transport_security) == (
        8456,
        "raw",
        "reality",
    )
    assert response.sni == "www.example.com"
    assert (response.reality_public_key, response.reality_short_id) == (_PUBLIC, "0123abcd")
    assert response.flow == "xtls-rprx-vision"
    inbound = _inbound(driver, "vless-reality-vision")
    stream = inbound["streamSettings"]
    assert stream["security"] == "reality"  # type: ignore[index]
    assert stream["realitySettings"] == {  # type: ignore[index]
        "dest": "www.example.com:443",
        "serverNames": ["www.example.com"],
        "privateKey": _PRIVATE,
        "shortIds": ["0123abcd"],
    }
    assert inbound["settings"]["clients"] == [  # type: ignore[index]
        {
            "id": str(request.client_uuid),
            "email": client_email(request.client_uuid),
            "flow": "xtls-rprx-vision",
        }
    ]
    # The server's private key never reaches a client.
    assert _PRIVATE not in response.model_dump_json()


def test_xhttp_rides_reality_without_vision(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    driver = _setup(tmp_path, monkeypatch)
    request = _provision_request(protocol_profile_code="vless-reality-xhttp")

    response = asyncio.run(driver.provision_client(request))

    assert (response.port, response.transport, response.path) == (8457, "xhttp", "/xhttp")
    assert response.transport_security == "reality" and response.flow is None
    inbound = _inbound(driver, "vless-reality-xhttp")
    assert "flow" not in inbound["settings"]["clients"][0]  # type: ignore[index]
    assert inbound["listen"] == "0.0.0.0"  # noqa: S104
