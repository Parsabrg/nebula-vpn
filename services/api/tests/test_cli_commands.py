"""The one-shot server and sweep commands: each disposes its engine and says
what it did."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

import nebula_api.cli as cli_module


@pytest.fixture
def engine(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    engine = MagicMock()
    engine.dispose = AsyncMock()
    monkeypatch.setattr(cli_module, "Settings", lambda: MagicMock())
    monkeypatch.setattr(cli_module, "_build_engine", lambda _settings: engine)
    monkeypatch.setattr(cli_module, "create_session_factory", lambda _engine: MagicMock())
    monkeypatch.setattr(cli_module, "load_auth_key_material", lambda _settings: MagicMock())
    monkeypatch.setattr(cli_module, "_agents_keeping_counters", lambda *_: MagicMock())
    return engine


def lock(acquired: bool) -> object:
    @asynccontextmanager
    async def held(_sessions: object) -> AsyncIterator[bool]:
        yield acquired

    return held


def sweep(problems: bool) -> SimpleNamespace:
    return SimpleNamespace(
        checked=3,
        in_sync=2,
        repaired=1,
        repair_failed=0,
        ambiguous=0,
        errored=0,
        servers=2,
        removed=1,
        kept=4,
        skipped=0,
        had_problems=problems,
    )


@pytest.mark.parametrize("changed", [True, False])
def test_disabling_a_protocol(
    engine: MagicMock,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    changed: bool,
) -> None:
    monkeypatch.setattr(cli_module, "disable_server_capability", AsyncMock(return_value=changed))
    code = asyncio.run(
        cli_module.run_disable_server_capability(server_code="nl", protocol_profile_code="vmess")
    )
    assert code == 0
    engine.dispose.assert_awaited_once_with()
    out = capsys.readouterr().out
    assert ("Disabled" in out) is changed


def test_creating_a_server_and_granting_it(
    engine: MagicMock, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(
        cli_module,
        "create_vpn_server",
        AsyncMock(return_value=SimpleNamespace(vpn_server_id=uuid4())),
    )
    monkeypatch.setattr(
        cli_module,
        "grant_user_server_access",
        AsyncMock(return_value=SimpleNamespace(user_id=uuid4(), profile_codes=["hysteria2"])),
    )
    assert (
        asyncio.run(
            cli_module.run_create_vpn_server(
                code="nl",
                display_name="Netherlands",
                agent_host="10.0.0.3",
                agent_port=9443,
                public_host="nl.example.org",
                wireguard_client_pool=None,
                wireguard_gateway_address=None,
                maximum_devices=100,
                state="ACTIVE",
            )
        )
        == 0
    )
    assert (
        asyncio.run(cli_module.run_grant_user_access(user_email="a@example.org", server_code="nl"))
        == 0
    )
    out = capsys.readouterr().out
    assert "Created VPN server 'nl'" in out
    assert "1 profile: hysteria2" in out


@pytest.mark.parametrize("name", ["run_reconcile_wireguard", "run_reconcile_xray"])
def test_a_reconciliation_pass_skips_while_another_runs(
    engine: MagicMock,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    name: str,
) -> None:
    monkeypatch.setattr(cli_module, "reconciliation_lock", lock(False))
    assert asyncio.run(getattr(cli_module, name)()) == 0
    assert "skipped" in capsys.readouterr().out
    engine.dispose.assert_awaited_once_with()


@pytest.mark.parametrize("problems", [False, True])
def test_reconciliation_and_orphan_prune_report_problems_in_the_exit_code(
    engine: MagicMock,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    problems: bool,
) -> None:
    monkeypatch.setattr(cli_module, "reconciliation_lock", lock(True))
    for name in ("run_reconciliation", "run_xray_reconciliation", "run_xray_orphan_prune"):
        monkeypatch.setattr(cli_module, name, AsyncMock(return_value=sweep(problems)))
    codes = [
        asyncio.run(cli_module.run_reconcile_wireguard()),
        asyncio.run(cli_module.run_reconcile_xray()),
        asyncio.run(cli_module.run_prune_xray_orphans()),
    ]
    assert codes == [int(problems)] * 3
    out = capsys.readouterr().out
    assert "Reconciled 3 peer(s)" in out
    assert "Reconciled 3 xray client(s)" in out
    assert "Pruned 2 server(s)" in out
