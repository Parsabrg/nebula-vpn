"""`nebula-api push-relays`, with the database faked."""

import asyncio
from typing import cast
from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine

import nebula_api.cli as cli
from nebula_api.topology_admin.service import TopologyAdminService


def test_push_relays_names_the_servers_it_missed(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    engine = MagicMock()
    engine.dispose = AsyncMock()
    monkeypatch.setattr(cli, "create_database_engine", lambda *_a, **_k: cast(AsyncEngine, engine))
    push = AsyncMock(return_value=["tehran"])
    monkeypatch.setattr(TopologyAdminService, "push_all_relays", push)

    # A server out of reach is not a failed sweep: it hears at its check-in.
    assert asyncio.run(cli.run_push_relays()) == 0
    assert "Not reached: tehran" in capsys.readouterr().out
    push.assert_awaited_once()
    engine.dispose.assert_awaited_once()
