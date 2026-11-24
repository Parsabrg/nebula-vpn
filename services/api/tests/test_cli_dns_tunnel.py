"""`nebula-api set-dns-tunnel` and `push-dns-tunnels`, with the database faked."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from types import SimpleNamespace
from typing import cast
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine

import nebula_api.cli as cli
import nebula_api.dns_tunnels as tunnels
from nebula_api.db.engine import SessionFactory

SERVER = uuid4()


@pytest.fixture
def engine(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    engine = MagicMock()
    engine.dispose = AsyncMock()
    session = MagicMock()
    session.scalar = AsyncMock(
        side_effect=lambda statement: (
            SERVER
            if "nl" in str(statement.compile(compile_kwargs={"literal_binds": True}))
            else None
        )
    )

    @asynccontextmanager
    async def opened() -> AsyncIterator[MagicMock]:
        yield session

    monkeypatch.setattr(cli, "create_database_engine", lambda *_a, **_k: cast(AsyncEngine, engine))
    monkeypatch.setattr(cli, "create_session_factory", lambda _engine: cast(SessionFactory, opened))
    return engine


def test_set_saves_pushes_and_says_so(
    engine: MagicMock,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path: Path,
) -> None:
    saved = AsyncMock()
    monkeypatch.setattr(cli, "set_tunnel", saved)
    monkeypatch.setattr(cli, "push_dns_tunnel", AsyncMock(return_value=False))
    key = tmp_path / "key"
    key.write_text("a" * 32 + "\n")

    code = asyncio.run(
        cli.run_set_dns_tunnel(
            server_code="nl", domains="T1.example.org, b.example.eu", key_file=key
        )
    )

    assert code == 0
    assert saved.await_args is not None
    assert saved.await_args.kwargs == {
        "server_id": SERVER,
        "domains": ["t1.example.org", "b.example.eu"],
        "key": "a" * 32,
    }
    assert "told at the next sweep" in capsys.readouterr().out
    engine.dispose.assert_awaited_once()


def test_set_refuses_bad_input_and_unknown_servers(engine: MagicMock, tmp_path: Path) -> None:
    bad_key = tmp_path / "key"
    bad_key.write_text("short")
    assert (
        asyncio.run(cli.run_set_dns_tunnel(server_code="nl", domains="not a name", key_file=None))
        == 2
    )
    assert (
        asyncio.run(
            cli.run_set_dns_tunnel(server_code="nl", domains="t.example.org", key_file=bad_key)
        )
        == 2
    )
    assert (
        asyncio.run(
            cli.run_set_dns_tunnel(server_code="nope", domains="t.example.org", key_file=None)
        )
        == 1
    )


def test_push_names_the_servers_it_missed(
    engine: MagicMock, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(cli, "push_all_dns_tunnels", AsyncMock(return_value=["tehran"]))
    assert asyncio.run(cli.run_push_dns_tunnels()) == 0
    assert "Not reached: tehran" in capsys.readouterr().out


def test_port_53_probe_counts_any_answer(monkeypatch: pytest.MonkeyPatch) -> None:
    class Socket:
        def __init__(self, reply: bytes | None) -> None:
            self.reply = reply

        def __enter__(self) -> "Socket":
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def settimeout(self, _t: float) -> None:
            return None

        def sendto(self, data: bytes, address: tuple[str, int]) -> None:
            assert address[1] == 53 and data.endswith(b"\x00\x10\x00\x01")

        def recv(self, _n: int) -> bytes:
            if self.reply is None:
                raise TimeoutError
            return self.reply

    for reply, expected in ((b"x" * 12, True), (None, False)):
        fake = SimpleNamespace(AF_INET=2, SOCK_DGRAM=2, socket=lambda *_a, r=reply: Socket(r))
        monkeypatch.setattr(tunnels, "socket", fake)
        assert asyncio.run(tunnels._answers_on_53("203.0.113.20", "t.example.org")) is expected
