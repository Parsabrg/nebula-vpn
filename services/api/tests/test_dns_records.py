"""The deployment's DNS record list and how each answer is judged."""

import asyncio
from typing import cast
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from test_relays_admin import FakeAuth

import nebula_api.cli as cli
import nebula_api.topology_admin.dns_records_routes as routes
from nebula_api import dns_records
from nebula_api.auth.admin_service import AdminAuthService
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.dns_records import (
    UNKNOWN_ADDRESS,
    Record,
    ServerAddress,
    judge,
    needed,
)
from nebula_api.dns_tunnels import TunnelEntry
from nebula_api.settings import Settings

SETTINGS = Settings(
    env="test",
    public_ip="198.51.100.7",
    api_public_url="https://api.vpn.example.org",
    admin_public_url="https://panel.vpn.example.org",
    cdn_host="cdn.example.org, cdn2.example.net",
)
SERVERS = [
    # The first server talks to its agent privately and was seeded by address.
    ServerAddress("de-1", "198.51.100.7", "172.30.101.1"),
    # Joined servers enrolled from their public address.
    ServerAddress("nl", "nl.vpn.example.org", "203.0.113.20"),
    ServerAddress("thr", "thr.vpn.example.org", "203.0.113.30"),
]
TUNNELS = [TunnelEntry(uuid4(), "nl", "nl.vpn.example.org", ["t.example.org"], "k" * 32)]


def as_tuples(records: list[Record]) -> list[tuple[str, str, str, str, bool]]:
    return [(r.name, r.type, r.value, r.purpose, r.proxied) for r in records]


def test_every_record_the_deployment_needs_once_each() -> None:
    assert as_tuples(needed(SETTINGS, SERVERS, TUNNELS)) == [
        ("panel.vpn.example.org", "A", "198.51.100.7", "control-plane", False),
        ("api.vpn.example.org", "A", "198.51.100.7", "control-plane", False),
        ("nl.vpn.example.org", "A", "203.0.113.20", "server", False),
        ("thr.vpn.example.org", "A", "203.0.113.30", "server", False),
        ("cdn.example.org", "A", "198.51.100.7", "cdn", True),
        ("cdn2.example.net", "A", "198.51.100.7", "cdn", True),
        ("t.example.org", "NS", "ns-t.example.org", "dns-tunnel", False),
        ("ns-t.example.org", "A", "203.0.113.20", "dns-tunnel", False),
    ]


def test_a_first_server_known_by_name_points_at_the_installers_address() -> None:
    first = ServerAddress("de-1", "vpn.example.org", "172.30.101.1")
    records = needed(SETTINGS, [first], [])
    assert ("vpn.example.org", "A", "198.51.100.7", "server", False) in as_tuples(records)


def test_without_the_address_the_value_says_so() -> None:
    settings = Settings(env="test", admin_public_url="https://panel.example.org")
    first = ServerAddress("de-1", "vpn.example.org", "172.30.101.1")
    values = {r.name: r.value for r in needed(settings, [first], [])}
    assert values == {"panel.example.org": UNKNOWN_ADDRESS, "vpn.example.org": UNKNOWN_ADDRESS}


def test_local_and_address_urls_need_no_record() -> None:
    settings = Settings(
        env="test", api_public_url="http://localhost:8000", admin_public_url="https://203.0.113.5"
    )
    assert needed(settings, [], []) == []


A = Record("api.vpn.example.org", "A", "198.51.100.7", "control-plane")
CDN = Record("cdn.example.org", "A", "198.51.100.7", "cdn", proxied=True)
NS = Record("t.example.org", "NS", "ns-t.example.org", "dns-tunnel")


@pytest.mark.parametrize(
    ("record", "found", "ok", "detail"),
    [
        (A, [], False, "api.vpn.example.org has no A record yet"),
        (A, ["198.51.100.7"], True, "api.vpn.example.org → 198.51.100.7"),
        (A, ["203.0.113.9"], False, "points at 203.0.113.9, not 198.51.100.7"),
        (CDN, ["104.21.1.1", "172.67.1.1"], True, "goes through the CDN"),
        (CDN, ["198.51.100.7"], False, "points straight at the server: turn the CDN proxy on"),
        (NS, ["ns-t.example.org"], True, "t.example.org → ns-t.example.org"),
        (NS, ["ns1.provider.net"], False, "points at ns1.provider.net, not ns-t.example.org"),
    ],
)
def test_each_answer_is_judged(record: Record, found: list[str], ok: bool, detail: str) -> None:
    status = judge(record, found)
    assert (status.ok, status.detail) == (ok, detail)


def test_an_unknown_address_is_never_reported_as_working() -> None:
    record = Record("vpn.example.org", "A", UNKNOWN_ADDRESS, "server")
    assert not judge(record, ["198.51.100.7"]).ok


def test_a_failed_lookup_is_reported_not_raised(monkeypatch: pytest.MonkeyPatch) -> None:

    async def doh(client: object, name: str, kind: str) -> list[str]:
        if name == "api.vpn.example.org":
            raise httpx.ConnectError("filtered")
        return ["198.51.100.7"]

    monkeypatch.setattr(dns_records, "doh", doh)
    other = Record("panel.vpn.example.org", "A", "198.51.100.7", "control-plane")
    statuses = asyncio.run(dns_records.check([A, other]))
    assert [(s.ok, s.detail) for s in statuses] == [
        (False, "the DNS lookup failed; try again"),
        (True, "panel.vpn.example.org → 198.51.100.7"),
    ]


def _admin_client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    async def servers(_sessions: object) -> list[ServerAddress]:
        return SERVERS

    async def list_tunnels(_sessions: object) -> list[TunnelEntry]:
        return TUNNELS

    async def check(records: list[Record]) -> list[dns_records.Status]:
        return [judge(r, [r.value] if r.purpose != "cdn" else ["104.21.1.1"]) for r in records]

    for name, fake in (("servers", servers), ("list_tunnels", list_tunnels), ("check", check)):
        monkeypatch.setattr(routes, name, fake)
    app = FastAPI()
    app.state.settings = SETTINGS
    app.state.admin_auth_service = cast(AdminAuthService, FakeAuth(True))
    app.state.dns_tunnel_sessions = object()
    install_auth_http_safeguards(app, SETTINGS)
    app.include_router(routes.router)
    client = TestClient(app)
    client.cookies.set(SETTINGS.admin_cookie_name, "v1.session-canary")
    client.cookies.set(SETTINGS.admin_csrf_cookie_name, "v1.csrf-canary")
    return client


def test_the_panel_gets_every_record_with_its_state(monkeypatch: pytest.MonkeyPatch) -> None:
    with _admin_client(monkeypatch) as client:
        response = client.get("/v1/admin/dns-records")
    assert response.status_code == 200
    items = response.json()["items"]
    assert len(items) == 8
    assert all(item["ok"] for item in items)
    assert items[4] == {
        "name": "cdn.example.org",
        "type": "A",
        "value": "198.51.100.7",
        "purpose": "cdn",
        "proxied": True,
        "ok": True,
        "found": ["104.21.1.1"],
        "detail": "goes through the CDN",
    }


def test_the_cli_lists_them_and_fails_when_one_needs_fixing(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    engine = MagicMock()
    engine.dispose = AsyncMock()
    monkeypatch.setattr(cli, "Settings", lambda: SETTINGS)
    monkeypatch.setattr(cli, "_build_engine", lambda _settings: engine)
    monkeypatch.setattr(cli, "create_session_factory", lambda _engine: object())

    async def servers(_sessions: object) -> list[ServerAddress]:
        return SERVERS[:2]

    async def no_tunnels(_sessions: object) -> list[TunnelEntry]:
        return []

    async def check(records: list[Record]) -> list[dns_records.Status]:
        return [judge(r, [] if r.name.startswith("nl.") else [r.value]) for r in records]

    monkeypatch.setattr(cli, "dns_record_servers", servers)
    monkeypatch.setattr(cli, "list_tunnels", no_tunnels)
    monkeypatch.setattr(cli, "check_dns_records", check)

    assert asyncio.run(cli.run_dns_records()) == 1
    lines = capsys.readouterr().out.splitlines()
    assert (
        "FIX A  nl.vpn.example.org -> 203.0.113.20: nl.vpn.example.org has no A record yet" in lines
    )
    assert (
        lines[0]
        == "ok  A  panel.vpn.example.org -> 198.51.100.7: panel.vpn.example.org → 198.51.100.7"
    )
    engine.dispose.assert_awaited_once()


def test_a_delegation_is_read_from_the_parent_zone_not_the_tunnel(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import dns.asyncquery
    import dns.flags
    import dns.message
    import dns.rrset

    zone_ns = {"example.org": ["ns1.dns-host.net", "ns2.dns-host.net"]}
    addresses = {"ns1.dns-host.net": ["192.0.2.1"], "ns2.dns-host.net": ["192.0.2.2"]}
    asked: list[tuple[str, str, bool]] = []

    async def doh(_client: object, name: str, kind: str) -> list[str]:
        return zone_ns.get(name, []) if kind == "NS" else addresses.get(name, [])

    async def udp(query: dns.message.Message, where: str, **_: object) -> dns.message.Message:
        asked.append((str(query.question[0].name), where, bool(query.flags & dns.flags.RD)))
        if where == "192.0.2.1":
            raise TimeoutError
        reply = dns.message.make_response(query)
        reply.authority.append(
            dns.rrset.from_text("t.sub.example.org.", 300, "IN", "NS", "ns-t.sub.example.org.")
        )
        return reply

    monkeypatch.setattr(dns_records, "doh", doh)
    monkeypatch.setattr(dns.asyncquery, "udp", udp)

    async def run() -> list[str]:
        async with httpx.AsyncClient() as client:
            return await dns_records.delegated_to(client, "t.sub.example.org")

    assert asyncio.run(run()) == ["ns-t.sub.example.org"]
    # sub.example.org has no NS of its own, so the zone is example.org; the
    # first nameserver timed out; neither question asked for recursion.
    assert asked == [
        ("t.sub.example.org.", "192.0.2.1", False),
        ("t.sub.example.org.", "192.0.2.2", False),
    ]


def test_before_the_installer_wrote_the_address_the_first_servers_is_used() -> None:
    settings = Settings(env="test", admin_public_url="https://panel.example.org")
    first = ServerAddress("de-1", "198.51.100.7", "172.30.101.1")
    assert as_tuples(needed(settings, [first], [])) == [
        ("panel.example.org", "A", "198.51.100.7", "control-plane", False)
    ]
