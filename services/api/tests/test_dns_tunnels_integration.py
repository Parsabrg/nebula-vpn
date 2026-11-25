"""DNS tunnels against real PostgreSQL: set, change, push and remove one, and
the checks an administrator sees (with the public DNS faked)."""

import asyncio
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import cast
from uuid import uuid4

import httpx
import pytest

import nebula_api.dns_tunnels as tunnels
from nebula_api.agent_client.client import AgentClient, AgentUnreachable
from nebula_api.agent_client.models import SetDnsTunnelRequest
from nebula_api.db.engine import create_database_engine, create_session_factory
from nebula_api.topology_seed import create_vpn_server


class FakeAgent:
    def __init__(self, sent: dict[str, SetDnsTunnelRequest], host: str) -> None:
        self.sent = sent
        self.host = host

    async def set_dns_tunnel(self, request: SetDnsTunnelRequest) -> None:
        if self.host.startswith("away"):
            raise AgentUnreachable("unreachable")
        self.sent[self.host] = request


def _builder(sent: dict[str, SetDnsTunnelRequest]):  # type: ignore[no-untyped-def]
    def build(host: str, port: int) -> AgentClient:
        del port

        @asynccontextmanager
        async def opened() -> AsyncIterator[FakeAgent]:
            yield FakeAgent(sent, host)

        return cast(AgentClient, opened())

    return build


@pytest.mark.skipif(
    not os.environ.get("NEBULA_DATABASE_URL"), reason="PostgreSQL is not configured"
)
def test_a_tunnel_is_set_changed_pushed_and_removed() -> None:
    engine = create_database_engine(os.environ["NEBULA_DATABASE_URL"])
    sessions = create_session_factory(engine)
    unique = uuid4().hex[:10]
    sent: dict[str, SetDnsTunnelRequest] = {}

    async def scenario() -> None:
        ids = {}
        for name in ("here", "away"):
            created = await create_vpn_server(
                sessions,
                code=f"dns-{name}-{unique}",
                display_name="DNS tunnel test",
                agent_host=f"{name}-{unique}.internal",
                agent_port=9443,
                public_host=f"{name}-{unique}.internal",
                wireguard_client_pool=None,
                wireguard_gateway_address=None,
                maximum_devices=10,
                state="active",
            )
            ids[name] = created.vpn_server_id
        here = ids["here"]

        made = await tunnels.set_tunnel(sessions, server_id=here, domains=[f"t.{unique}.org"])
        assert made is not None and len(made.key) == 32
        kept = "a" * 32
        moved = await tunnels.set_tunnel(
            sessions, server_id=here, domains=[f"t.{unique}.org", f"b.{unique}.eu"], key=kept
        )
        assert moved is not None and moved.key == kept
        listed = [t for t in await tunnels.list_tunnels(sessions) if t.server_id == here]
        assert listed[0].domains == [f"t.{unique}.org", f"b.{unique}.eu"]

        assert await tunnels.push(sessions, _builder(sent), here) is True
        assert sent[f"here-{unique}.internal"].key == kept
        missed = await tunnels.push_all(sessions, _builder(sent))
        assert f"dns-away-{unique}" in missed
        assert f"dns-here-{unique}" not in missed
        assert await tunnels.push(sessions, _builder(sent), uuid4()) is False

        removed = await tunnels.set_tunnel(sessions, server_id=here, domains=[])
        assert removed is not None and removed.key == ""
        assert not [t for t in await tunnels.list_tunnels(sessions) if t.server_id == here]
        await tunnels.push(sessions, _builder(sent), here)
        assert sent[f"here-{unique}.internal"].domains == []
        assert await tunnels.set_tunnel(sessions, server_id=uuid4(), domains=["x.org"]) is None

    try:
        asyncio.run(scenario())
    finally:
        asyncio.run(engine.dispose())


def test_the_checks_say_what_is_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    answers = {
        ("nl.example.org", "A"): ["203.0.113.20"],
        ("t2.example.org", "NS"): ["ns-t2.example.org"],
        ("ns-t2.example.org", "A"): ["203.0.113.20"],
        ("t3.example.org", "NS"): ["ns.elsewhere.org"],
        ("ns.elsewhere.org", "A"): ["198.51.100.1"],
    }

    async def doh(_client: object, name: str, kind: str) -> list[str]:
        return answers.get((name, kind), [])

    async def answers_on_53(server_ip: str, name: str) -> bool:
        return name == "t2.example.org"

    async def delegated_to(_client: object, name: str) -> list[str]:
        return answers.get((name, "NS"), [])

    monkeypatch.setattr(tunnels, "_doh", doh)
    monkeypatch.setattr(tunnels, "_delegated_to", delegated_to)
    monkeypatch.setattr(tunnels, "_answers_on_53", answers_on_53)

    ip, good = asyncio.run(tunnels.check("t2.example.org", "nl.example.org"))
    assert ip == "203.0.113.20" and [c.ok for c in good] == [True, True]
    _, elsewhere = asyncio.run(tunnels.check("t3.example.org", "203.0.113.20"))
    assert not elsewhere[0].ok
    assert elsewhere[0].detail == "t3.example.org points to ns.elsewhere.org, not this server"
    _, missing = asyncio.run(tunnels.check("t4.example.org", "203.0.113.20"))
    assert missing[0].detail == "t4.example.org has no NS record yet" and not missing[1].ok


def test_a_dns_question_and_a_doh_answer() -> None:
    query = tunnels._query("abcd.t2.example.org")
    assert query[12:].startswith(b"\x04abcd\x02t2\x07example\x03org\x00")
    assert query[-4:] == b"\x00\x10\x00\x01"  # TXT, IN

    def reply(request: httpx.Request) -> httpx.Response:
        assert request.url.params["type"] == "NS"
        return httpx.Response(
            200,
            json={"Answer": [{"type": 2, "data": "NS-T2.example.org."}, {"type": 5, "data": "x"}]},
        )

    async def ask() -> list[str]:
        async with httpx.AsyncClient(transport=httpx.MockTransport(reply)) as client:
            return await tunnels._doh(client, "t2.example.org", "NS")

    assert asyncio.run(ask()) == ["ns-t2.example.org"]
