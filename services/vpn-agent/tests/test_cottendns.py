"""The DNS tunnel's server config (plan 10)."""

import asyncio
import os
from pathlib import Path, PurePosixPath

import pytest
from pydantic import ValidationError

import nebula_agent.drivers.cottendns as cottendns
from nebula_agent.drivers._exec import CompletedRun
from nebula_agent.drivers.cottendns import apply_cottendns, render_cottendns_config
from nebula_agent.settings import Settings


def _settings(tmp_path: Path, **overrides: object) -> Settings:
    values: dict[str, object] = {
        "env": "test",
        "xray_vlessenc_enabled": True,
        "xray_vlessenc_decryption": "mlkem768x25519plus.native.600s.server-key",
        "xray_vlessenc_encryption": "mlkem768x25519plus.native.0rtt.client-key",
        "cottendns_domains": "t.example.org",
        "cottendns_config_file": PurePosixPath(str(tmp_path / "server_config.toml")),
    }
    values.update(overrides)
    return Settings(**values)  # type: ignore[arg-type]


def test_none_without_a_domain(tmp_path: Path) -> None:
    assert render_cottendns_config(_settings(tmp_path, cottendns_domains="")) is None


def test_forwards_only_to_vless_encryption_with_aes_256(tmp_path: Path) -> None:
    rendered = render_cottendns_config(_settings(tmp_path))
    assert rendered is not None
    for line in (
        'DOMAIN = ["t.example.org"]',
        'PROTOCOL_TYPE = "TCP"',
        'FORWARD_IP = "127.0.0.1"',
        "FORWARD_PORT = 8453",
        'UDP_HOST = "127.0.0.1"',
        "UDP_PORT = 5310",
        "DATA_ENCRYPTION_METHOD = 5",
        "ENCRYPTION_AUTO_DETECT = false",
        'ENCRYPTION_KEY_FILE = "/etc/nebula/secrets/cottendns_key"',
    ):
        assert line in rendered.splitlines()


def test_every_name_is_served(tmp_path: Path) -> None:
    rendered = render_cottendns_config(
        _settings(tmp_path, cottendns_domains="nt.example.org,t.backup.eu.org")
    )
    assert rendered is not None
    assert 'DOMAIN = ["nt.example.org", "t.backup.eu.org"]' in rendered.splitlines()


@pytest.mark.parametrize(
    "overrides",
    [
        {"xray_vlessenc_enabled": False},
        {"cottendns_domains": "not a name"},
        {"cottendns_domains": "t.example.org,"},
        {"cottendns_listen": "0.0.0.0:53"},
    ],
)
def test_refused_settings(tmp_path: Path, overrides: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        _settings(tmp_path, **overrides)


def test_written_and_restarted_only_when_changed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    restarts: list[list[str]] = []

    async def fake_run(argv: list[str], **_kwargs: object) -> CompletedRun:
        restarts.append(argv)
        return CompletedRun(returncode=0, stdout=b"", stderr=b"")

    monkeypatch.setattr(cottendns, "run_fixed_argv", fake_run)
    settings = _settings(tmp_path)

    assert asyncio.run(apply_cottendns(settings)) is True
    assert asyncio.run(apply_cottendns(settings)) is False
    assert restarts == [["/usr/bin/systemctl", "restart", "nebula-cottendns.service"]]
    assert (tmp_path / "server_config.toml").read_text() == render_cottendns_config(settings)
    if os.name == "posix":
        assert (tmp_path / "server_config.toml").stat().st_mode & 0o777 == 0o640
    assert asyncio.run(apply_cottendns(_settings(tmp_path, cottendns_domains=""))) is False
