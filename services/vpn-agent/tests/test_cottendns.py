"""The DNS tunnel's server (plan 10): config from the control plane's request."""

from collections.abc import Iterator
from pathlib import Path, PurePosixPath

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

import nebula_agent.drivers.cottendns as cottendns
from nebula_agent.drivers._exec import CompletedRun
from nebula_agent.drivers.cottendns import render_cottendns_config
from nebula_agent.drivers.fake import FakeXrayRunner
from nebula_agent.ledger import OperationLedger
from nebula_agent.main import create_app
from nebula_agent.settings import Settings

KEY = "0123456789abcdef" * 2  # gitleaks:allow (test value)


def _settings(tmp_path: Path, **overrides: object) -> Settings:
    values: dict[str, object] = {
        "env": "test",
        "xray_vlessenc_enabled": True,
        "xray_vlessenc_decryption": "mlkem768x25519plus.native.600s.server-key",
        "xray_vlessenc_encryption": "mlkem768x25519plus.native.0rtt.client-key",
        "cottendns_config_file": PurePosixPath(str(tmp_path / "server_config.toml")),
    }
    values.update(overrides)
    return Settings(**values)  # type: ignore[arg-type]


def test_the_config_forwards_only_to_vless_encryption(tmp_path: Path) -> None:
    rendered = render_cottendns_config(
        _settings(tmp_path, cottendns_listen="203.0.113.5:53"), ["nt.example.org", "t.backup.eu"]
    )
    assert 'DOMAIN = ["nt.example.org", "t.backup.eu"]' in rendered
    assert 'FORWARD_IP = "127.0.0.1"' in rendered
    assert 'UDP_HOST = "203.0.113.5"' in rendered
    assert "UDP_PORT = 53" in rendered
    assert "ENCRYPTION_AUTO_DETECT = false" in rendered
    assert f'ENCRYPTION_KEY_FILE = "{tmp_path / "key"}"' in rendered.replace("\\\\", "\\")


@pytest.mark.parametrize("listen", ["203.0.113.5", "host:53", "[::]:53"])
def test_a_listen_address_must_be_ipv4_and_port(tmp_path: Path, listen: str) -> None:
    with pytest.raises(ValidationError):
        _settings(tmp_path, cottendns_listen=listen)


@pytest.fixture
def systemctl(monkeypatch: pytest.MonkeyPatch) -> list[list[str]]:
    calls: list[list[str]] = []

    async def fake_run(argv: list[str], *, timeout_seconds: float) -> CompletedRun:
        del timeout_seconds
        calls.append(argv)
        return CompletedRun(returncode=0, stdout=b"", stderr=b"")

    monkeypatch.setattr(cottendns, "run_fixed_argv", fake_run)
    return calls


def _client(settings: Settings, tmp_path: Path) -> Iterator[TestClient]:
    ledger = OperationLedger(PurePosixPath(str(tmp_path / "ledger.jsonl")), 100)
    app = create_app(settings, xray_driver=FakeXrayRunner(), ledger=ledger)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def client(tmp_path: Path) -> Iterator[TestClient]:
    yield from _client(_settings(tmp_path), tmp_path)


def test_a_tunnel_is_served_then_removed(
    client: TestClient, tmp_path: Path, systemctl: list[list[str]]
) -> None:
    body = {"domains": ["nt.example.org"], "key": KEY}
    assert client.post("/v1/dns-tunnel", json=body).status_code == 204
    assert client.post("/v1/dns-tunnel", json=body).status_code == 204  # unchanged
    assert (tmp_path / "key").read_text() == KEY + "\n"
    lines = (tmp_path / "server_config.toml").read_text().splitlines()
    assert 'DOMAIN = ["nt.example.org"]' in lines

    assert client.post("/v1/dns-tunnel", json={"domains": []}).status_code == 204
    assert not (tmp_path / "server_config.toml").exists()
    assert not (tmp_path / "key").exists()
    assert [argv[1] for argv in systemctl] == ["restart", "stop"]


@pytest.mark.parametrize(
    "body",
    [
        {"domains": ["nt.example.org"]},  # no key
        {"domains": ["not a name"], "key": KEY},
        {"domains": ["nt.example.org"], "key": "short"},
    ],
)
def test_bad_requests_change_nothing(
    client: TestClient, tmp_path: Path, systemctl: list[list[str]], body: dict[str, object]
) -> None:
    assert client.post("/v1/dns-tunnel", json=body).status_code == 422
    assert not (tmp_path / "server_config.toml").exists()
    assert systemctl == []


def test_refused_without_vless_encryption(tmp_path: Path, systemctl: list[list[str]]) -> None:
    settings = _settings(tmp_path, xray_vlessenc_enabled=False)
    for client in _client(settings, tmp_path):
        response = client.post("/v1/dns-tunnel", json={"domains": ["nt.example.org"], "key": KEY})
        assert response.status_code == 409
    assert systemctl == []
