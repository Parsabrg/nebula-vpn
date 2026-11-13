"""Real PostgreSQL: a relay added in the panel is read back as a relay, its
code is unique, and removing it removes it."""

import asyncio
import os
from typing import cast
from uuid import uuid4

import pytest
from sqlalchemy import text

from nebula_api.agent_client.client import AgentClient, AgentClientBuilder
from nebula_api.agent_client.models import SetRelayRequest
from nebula_api.db.engine import create_database_engine, create_session_factory
from nebula_api.relays import RelayCatalog, load_panel_relays
from nebula_api.topology_admin.service import TopologyAdminService


@pytest.mark.skipif(
    not os.environ.get("NEBULA_DATABASE_URL"), reason="PostgreSQL is not configured"
)
def test_a_panel_relay_round_trips() -> None:
    engine = create_database_engine(os.environ["NEBULA_DATABASE_URL"])
    factory = create_session_factory(engine)
    sent: list[tuple[str, SetRelayRequest]] = []

    class _Agent:
        def __init__(self, host: str) -> None:
            self._host = host

        async def __aenter__(self) -> "_Agent":
            return self

        async def __aexit__(self, *exc_info: object) -> None:
            return None

        async def set_relay(self, request: SetRelayRequest) -> None:
            sent.append((self._host, request))

    def builder(host: str, port: int) -> AgentClient:
        return cast(AgentClient, _Agent(host))

    service = TopologyAdminService(factory, agent_client_builder=cast(AgentClientBuilder, builder))
    unique = uuid4().hex[:10]
    exit_ip = f"198.18.{int(unique[:2], 16)}.{int(unique[2:4], 16)}"
    exit_id, via_id, admin_id = uuid4(), uuid4(), uuid4()
    code = f"de-{unique}-via-thr"

    async def scenario() -> None:
        async with engine.begin() as connection:
            for server_id, name in ((exit_id, "de"), (via_id, "thr")):
                await connection.execute(
                    text(
                        "INSERT INTO vpn_servers "
                        "(id, code, display_name, state, agent_host, agent_port, public_host, "
                        "maximum_devices) VALUES "
                        "(:id, :code, :code, 'active', :agent, 9443, :public, 100)"
                    ),
                    {
                        "id": server_id,
                        "code": f"{name}-{unique}",
                        "agent": f"agent-{name}-{unique}.internal.test",
                        "public": exit_ip if name == "de" else f"{name}-{unique}.example.test",
                    },
                )
        try:
            await service.add_relay(
                code=code,
                display_name="Germany via Tehran",
                exit_server_id=exit_id,
                via_server_id=via_id,
                host="198.51.100.7",
                ports={"vless-tcp-tls": 443, "hysteria2": 443},
                admin_id=admin_id,
                request_id=uuid4(),
            )
            async with factory() as session:
                mine = [r for r in await load_panel_relays(session) if r.code == code]
            assert len(mine) == 1
            assert (mine[0].exit, mine[0].via, mine[0].ports) == (
                f"de-{unique}",
                f"thr-{unique}",
                {"vless-tcp-tls": 443, "hysteria2": 443},
            )
            assert any(r.code == code for r in await RelayCatalog(factory).relays())
            with pytest.raises(ValueError):
                await service.add_relay(
                    code=code,
                    display_name="Again",
                    exit_server_id=exit_id,
                    via_server_id=via_id,
                    host="198.51.100.7",
                    ports={"vless-tcp-tls": 443},
                    admin_id=admin_id,
                    request_id=uuid4(),
                )
            with pytest.raises(LookupError):
                await service.add_relay(
                    code=f"{code}-x",
                    display_name="Nowhere",
                    exit_server_id=uuid4(),
                    via_server_id=via_id,
                    host="198.51.100.7",
                    ports={"vless-tcp-tls": 443},
                    admin_id=admin_id,
                    request_id=uuid4(),
                )
            # The relay server's agent is asked to forward to the exit.
            assert await service.push_relay(
                via_server_id=via_id, report_base="https://cdn.example.test", report_token="t" * 32
            )
            host, request = sent[-1]
            assert host == f"agent-thr-{unique}.internal.test"
            assert request.target == exit_ip
            assert request.report_url == f"https://cdn.example.test/v1/relays/{code}/up"
            # One exit per relay server.
            with pytest.raises(ValueError):
                await service.add_relay(
                    code=f"{code}-2",
                    display_name="Second",
                    exit_server_id=exit_id,
                    via_server_id=via_id,
                    host="198.51.100.7",
                    ports={"vless-tcp-tls": 443},
                    admin_id=admin_id,
                    request_id=uuid4(),
                )
            assert await service.remove_relay(code=code, admin_id=admin_id, request_id=uuid4())
            assert not await service.remove_relay(code=code, admin_id=admin_id, request_id=uuid4())
            # And once removed, asked to forward nothing.
            assert await service.push_relay(
                via_server_id=via_id, report_base="https://cdn.example.test", report_token=""
            )
            assert sent[-1][1].ports == []
        finally:
            async with engine.begin() as connection:
                await connection.execute(
                    text("DELETE FROM relay_routes WHERE code LIKE :c"), {"c": f"{code}%"}
                )
                for server_id in (exit_id, via_id):
                    await connection.execute(
                        text("DELETE FROM vpn_servers WHERE id = :id"), {"id": server_id}
                    )
            await engine.dispose()

    asyncio.run(scenario())
