"""Every DNS record the deployment needs, and whether each one works.

Names are made in several places -- the installer (the panel, the API and
each server's own name), the CDN route and the DNS tunnels -- and each used
to explain its own records in its own place. Here they are one list, built
from what the control plane already knows, so the panel can show what is
missing in one view and a DNS provider can create it.
"""

from __future__ import annotations

import ipaddress
from collections.abc import Iterable
from dataclasses import dataclass
from typing import TYPE_CHECKING, Literal
from urllib.parse import urlparse

import dns.asyncquery
import dns.exception
import dns.flags
import dns.message
import dns.rdatatype
import httpx
from sqlalchemy import select

from nebula_api.db.engine import SessionFactory
from nebula_api.models import VPNServer
from nebula_api.settings import Settings

if TYPE_CHECKING:
    from nebula_api.dns_tunnels import TunnelEntry

DOH = "https://cloudflare-dns.com/dns-query"
UNKNOWN_ADDRESS = "<this server's address>"
_TYPES = {"A": 1, "NS": 2, "CNAME": 5}

Kind = Literal["A", "NS"]
Purpose = Literal["control-plane", "server", "cdn", "dns-tunnel"]


@dataclass(frozen=True)
class Record:
    name: str
    type: Kind
    value: str
    purpose: Purpose
    # Through the CDN (Cloudflare's orange cloud) rather than straight to
    # the server: only the CDN names.
    proxied: bool = False


@dataclass(frozen=True)
class ServerAddress:
    code: str
    public_host: str
    agent_host: str


@dataclass(frozen=True)
class Status:
    record: Record
    ok: bool
    found: list[str]
    detail: str


def _is_ip(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return False
    return True


# Where an agent can sit that no one outside reaches: a private network,
# carrier-grade NAT, the machine itself, link-local.
_INTERNAL = [
    ipaddress.ip_network(net)
    for net in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "127.0.0.0/8")
] + [ipaddress.ip_network("169.254.0.0/16")]


def _public_ip(value: str) -> bool:
    if not _is_ip(value):
        return False
    address = ipaddress.ip_address(value)
    return address.version == 4 and not any(address in net for net in _INTERNAL)


def _host(url: str) -> str | None:
    host = (urlparse(url).hostname or "").lower()
    return host if host and "." in host and not _is_ip(host) else None


async def servers(sessions: SessionFactory) -> list[ServerAddress]:
    async with sessions() as session:
        rows = await session.execute(
            select(VPNServer.code, VPNServer.public_host, VPNServer.agent_host).order_by(
                VPNServer.code
            )
        )
        return [ServerAddress(code, public, agent) for code, public, agent in rows.all()]


def server_ip(server: ServerAddress, settings: Settings) -> str | None:
    """The address a server's name must point at. A joined server enrolled
    from its public address; the first one talks to its agent over a private
    network, so its address is the installer's (NEBULA_PUBLIC_IP), unless
    its public host is an address already."""

    for value in (server.agent_host, server.public_host):
        if _public_ip(value):
            return value
    return settings.public_ip or None


def tunnel_records(name: str, address: str) -> list[Record]:
    """A DNS tunnel's two records: the name delegated to a nameserver beside
    it (not inside it: a zone cannot hold glue for a name it delegates away),
    and that nameserver's address."""

    nameserver = "ns-" + name
    return [
        Record(name, "NS", nameserver, "dns-tunnel"),
        Record(nameserver, "A", address, "dns-tunnel"),
    ]


def needed(
    settings: Settings,
    servers: Iterable[ServerAddress],
    tunnels: Iterable[TunnelEntry],
) -> list[Record]:
    """Every record, once each, in the order an administrator makes them."""

    by_code = {server.code: server for server in servers}
    # The control plane's own server is the one its API reaches privately; a
    # server installed before NEBULA_PUBLIC_IP was written may still carry
    # its address as its public host.
    local = next((s for s in by_code.values() if not _public_ip(s.agent_host)), None)
    control_ip = settings.public_ip or (local and server_ip(local, settings)) or UNKNOWN_ADDRESS
    found: dict[tuple[str, str], Record] = {}

    def add(record: Record) -> None:
        found.setdefault((record.name, record.type), record)

    for url in (settings.admin_public_url, settings.api_public_url):
        if host := _host(url):
            add(Record(host, "A", control_ip, "control-plane"))
    for server in by_code.values():
        if not _is_ip(server.public_host) and "." in server.public_host:
            address = server_ip(server, settings) or UNKNOWN_ADDRESS
            add(Record(server.public_host.lower(), "A", address, "server"))
    for cdn in (part.strip().lower() for part in settings.cdn_host.split(",")):
        if cdn:
            add(Record(cdn, "A", control_ip, "cdn", proxied=True))
    for tunnel in tunnels:
        owner = by_code.get(tunnel.server_code)
        address = (owner and server_ip(owner, settings)) or UNKNOWN_ADDRESS
        for domain in tunnel.domains:
            for record in tunnel_records(domain, address):
                add(record)
    return list(found.values())


async def doh(client: httpx.AsyncClient, name: str, kind: str) -> list[str]:
    """What the public DNS answers, through Cloudflare's resolver."""

    response = await client.get(
        DOH, params={"name": name, "type": kind}, headers={"accept": "application/dns-json"}
    )
    response.raise_for_status()
    wanted = _TYPES[kind]
    return [
        str(answer["data"]).rstrip(".").lower()
        for answer in response.json().get("Answer", [])
        if answer.get("type") == wanted
    ]


async def delegated_to(client: httpx.AsyncClient, name: str) -> list[str]:
    """The nameservers the parent zone hands the name to.

    Not a recursive NS lookup: that one is answered by the delegated server
    itself, and a DNS tunnel server answers no NS question -- a working
    delegation looked missing. The parent zone's own nameserver, asked
    directly without recursion, gives the referral as it stands."""

    parent = name
    parent_ns: list[str] = []
    while "." in parent and not parent_ns:
        parent = parent.split(".", 1)[1]
        parent_ns = await doh(client, parent, "NS")
    for nameserver in parent_ns:
        for address in await doh(client, nameserver, "A"):
            query = dns.message.make_query(name, dns.rdatatype.NS)
            query.flags &= ~dns.flags.RD
            try:
                reply = await dns.asyncquery.udp(query, address, timeout=4)
            except (OSError, dns.exception.DNSException):
                continue
            return sorted(
                str(item.target).rstrip(".").lower()
                for rrset in (*reply.answer, *reply.authority)
                if rrset.rdtype == dns.rdatatype.NS and str(rrset.name).rstrip(".").lower() == name
                for item in rrset
            )
    return []


def judge(record: Record, found: list[str]) -> Status:
    """Whether what the public DNS answers is what the record should say."""

    if not found:
        return Status(record, False, found, f"{record.name} has no {record.type} record yet")
    if record.proxied:
        # A proxied name answers with the CDN's addresses, never the server's.
        if record.value in found:
            return Status(
                record, False, found, "points straight at the server: turn the CDN proxy on"
            )
        return Status(record, True, found, "goes through the CDN")
    if record.value == UNKNOWN_ADDRESS:
        return Status(
            record,
            False,
            found,
            "points at " + ", ".join(found) + "; this server's address is unknown",
        )
    if record.value in found:
        return Status(record, True, found, f"{record.name} → {record.value}")
    return Status(record, False, found, f"points at {', '.join(found)}, not {record.value}")


async def check(records: Iterable[Record]) -> list[Status]:
    """Each record as the public DNS sees it now."""

    statuses: list[Status] = []
    async with httpx.AsyncClient(timeout=6) as client:
        for record in records:
            try:
                found = await (
                    delegated_to(client, record.name)
                    if record.type == "NS"
                    else doh(client, record.name, record.type)
                )
            except httpx.HTTPError:
                statuses.append(Status(record, False, [], "the DNS lookup failed; try again"))
                continue
            statuses.append(judge(record, found))
    return statuses
