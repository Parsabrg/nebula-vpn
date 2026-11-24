"""DNS tunnels, one per server at most (docs/runbooks/dns-tunnel.md).

An administrator gives a server the names delegated to it (panel or
`nebula-api set-dns-tunnel`); the control plane keeps them with the tunnel's
key and tells the server's agent, which runs the tunnel server there
(services/vpn-agent api/v1_dns_tunnel.py). The reconcile sweep tells every
agent again, so a rebuilt server or a push that did not get through catches
up by itself. Signed-in apps get the list from GET /v1/dns-tunnel.

What an administrator cannot do from here is the DNS records themselves at
their DNS provider: `records` says which, and `check` whether they work.
"""

import asyncio
import logging
import re
import secrets
import socket
import struct
from dataclasses import dataclass
from uuid import UUID, uuid4

import httpx
from sqlalchemy import delete, select

from nebula_api.agent_client.client import (
    AgentClientBuilder,
    AgentRejected,
    AgentResponseAmbiguous,
    AgentResponseInvalid,
    AgentUnreachable,
)
from nebula_api.agent_client.models import SetDnsTunnelRequest
from nebula_api.auth.audit import add_audit_event
from nebula_api.db.engine import SessionFactory
from nebula_api.models import DnsTunnel, VPNServer

_LOGGER = logging.getLogger(__name__)

NAME = re.compile(r"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$")
MAX_NAMES = 4
_DOH = "https://cloudflare-dns.com/dns-query"


@dataclass(frozen=True)
class TunnelEntry:
    server_id: UUID
    server_code: str
    public_host: str
    domains: list[str]
    key: str


def clean_names(raw: list[str]) -> list[str]:
    """Lower-cased, unique, in order; ValueError for one that is not a name."""

    names: list[str] = []
    for name in (part.strip().lower().rstrip(".") for part in raw):
        if not name or name in names:
            continue
        if len(name) > 253 or not NAME.match(name):
            raise ValueError(f"not a DNS name: {name}")
        names.append(name)
    if len(names) > MAX_NAMES:
        raise ValueError(f"at most {MAX_NAMES} names")
    return names


async def list_tunnels(session_factory: SessionFactory) -> list[TunnelEntry]:
    async with session_factory() as session:
        rows = await session.execute(
            select(DnsTunnel, VPNServer)
            .join(VPNServer, VPNServer.id == DnsTunnel.vpn_server_id)
            .order_by(VPNServer.code)
        )
        return [
            TunnelEntry(
                server.id, server.code, server.public_host, list(tunnel.domains), tunnel.key
            )
            for tunnel, server in rows.tuples()
        ]


async def set_tunnel(
    session_factory: SessionFactory,
    *,
    server_id: UUID,
    domains: list[str],
    key: str | None = None,
    admin_id: UUID | None = None,
) -> TunnelEntry | None:
    """Give the server these names (none: no tunnel). A new tunnel gets a new
    key unless one is given (moving an existing tunnel here keeps its key, so
    apps that hold it keep working). None when there is no such server."""

    async with session_factory() as session:
        server = await session.get(VPNServer, server_id)
        if server is None:
            return None
        tunnel = await session.scalar(
            select(DnsTunnel).where(DnsTunnel.vpn_server_id == server_id).with_for_update()
        )
        if not domains:
            await session.execute(delete(DnsTunnel).where(DnsTunnel.vpn_server_id == server_id))
            reason = "dns_tunnel_removed"
        elif tunnel is None:
            tunnel = DnsTunnel(
                vpn_server_id=server_id, domains=domains, key=key or secrets.token_hex(16)
            )
            session.add(tunnel)
            reason = "dns_tunnel_set"
        else:
            tunnel.domains = domains
            if key:
                tunnel.key = key
            reason = "dns_tunnel_set"
        event = {
            "target_kind": "vpn_server",
            "target_id": server_id,
            "event_code": "server_changed",
            "outcome": "succeeded",
            "request_id": uuid4(),
            "reason_code": reason,
        }
        if admin_id is not None:
            add_audit_event(session, actor_kind="admin", actor_id=admin_id, **event)  # type: ignore[arg-type]
        else:
            # The installer or an operator's shell (nebula-api set-dns-tunnel).
            add_audit_event(session, actor_kind="system", actor_id=None, **event)  # type: ignore[arg-type]
        await session.commit()
        return TunnelEntry(
            server.id,
            server.code,
            server.public_host,
            list(domains),
            tunnel.key if domains and tunnel else "",
        )


async def push(
    session_factory: SessionFactory, builder: AgentClientBuilder, server_id: UUID
) -> bool:
    """Tell one server's agent its tunnel (or that it has none). True if taken."""

    async with session_factory() as session:
        server = await session.get(VPNServer, server_id)
        tunnel = await session.scalar(select(DnsTunnel).where(DnsTunnel.vpn_server_id == server_id))
        if server is None:
            return False
        host, port = server.agent_host, server.agent_port
    request = SetDnsTunnelRequest(
        domains=list(tunnel.domains) if tunnel else [], key=tunnel.key if tunnel else ""
    )
    try:
        async with builder(host, port) as agent:
            await agent.set_dns_tunnel(request)
    except AgentRejected as error:
        _LOGGER.warning("server %s refused its DNS tunnel: %s", server_id, error)
        return False
    except (AgentUnreachable, AgentResponseAmbiguous, AgentResponseInvalid):
        return False
    return True


async def push_all(session_factory: SessionFactory, builder: AgentClientBuilder) -> list[str]:
    """Tell every server's agent its tunnel; the codes of those not reached."""

    async with session_factory() as session:
        servers = (await session.execute(select(VPNServer.id, VPNServer.code))).all()
    results = await asyncio.gather(*(push(session_factory, builder, sid) for sid, _ in servers))
    return [code for (_, code), ok in zip(servers, results, strict=True) if not ok]


def records(name: str, server_ip: str) -> list[tuple[str, str, str]]:
    """The two records the DNS provider needs, as (name, type, value): the
    tunnel name delegated to a nameserver beside it (not inside it: a zone
    cannot hold glue for a name it delegates away), and that nameserver's
    address."""

    nameserver = "ns-" + name
    return [(name, "NS", nameserver), (nameserver, "A", server_ip)]


@dataclass(frozen=True)
class Check:
    key: str
    ok: bool
    detail: str


async def _doh(client: httpx.AsyncClient, name: str, kind: str) -> list[str]:
    response = await client.get(
        _DOH, params={"name": name, "type": kind}, headers={"accept": "application/dns-json"}
    )
    response.raise_for_status()
    wanted = {"A": 1, "NS": 2}[kind]
    return [
        str(answer["data"]).rstrip(".").lower()
        for answer in response.json().get("Answer", [])
        if answer.get("type") == wanted
    ]


def _query(name: str) -> bytes:
    header = struct.pack(">HHHHHH", secrets.randbits(16), 0x0100, 1, 0, 0, 0)
    labels = b"".join(bytes([len(part)]) + part.encode() for part in name.split("."))
    return header + labels + b"\x00" + struct.pack(">HH", 16, 1)  # TXT, IN


async def _answers_on_53(server_ip: str, name: str) -> bool:
    """Whether anything answers a DNS question for the name at the server."""

    def ask() -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            udp.settimeout(3)
            udp.sendto(_query(f"{secrets.token_hex(4)}.{name}"), (server_ip, 53))
            try:
                return len(udp.recv(512)) >= 12
            except OSError:
                return False

    return await asyncio.to_thread(ask)


async def check(name: str, public_host: str) -> tuple[str | None, list[Check]]:
    """The server's address, and whether the name reaches it: delegated (as
    the public DNS sees it) and answered on port 53."""

    checks: list[Check] = []
    async with httpx.AsyncClient(timeout=6) as client:
        try:
            addresses = (
                [public_host]
                if re.fullmatch(r"[0-9.]+", public_host)
                else await _doh(client, public_host, "A")
            )
        except httpx.HTTPError:
            addresses = []
        server_ip = addresses[0] if addresses else None
        try:
            nameservers = await _doh(client, name, "NS")
            glue = [ip for ns in nameservers for ip in await _doh(client, ns, "A")]
        except httpx.HTTPError:
            nameservers, glue = [], []
    if not nameservers:
        checks.append(Check("delegated", False, f"{name} has no NS record yet"))
    elif server_ip is None or server_ip not in glue:
        checks.append(
            Check("delegated", False, f"{name} points to {', '.join(nameservers)}, not this server")
        )
    else:
        checks.append(Check("delegated", True, f"{name} → {nameservers[0]} → {server_ip}"))
    answered = server_ip is not None and await _answers_on_53(server_ip, name)
    checks.append(
        Check(
            "answers",
            answered,
            "the tunnel answers on port 53"
            if answered
            else "nothing answers on port 53 (firewall, or port 53 owned by another program)",
        )
    )
    return server_ip, checks
