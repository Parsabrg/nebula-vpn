"""Ask every active server for its counters and fold them into the totals.

Runs on a timer beside the reconciliation sweep. The interval is a real
trade-off rather than a tuning knob: a counter that resets loses whatever was
served between the last poll and the restart, so a longer interval means more
traffic can go unrecorded. Polling costs one cheap call per server, so the
interval should be short -- but no interval closes the window entirely, which
is why the totals are described as accumulated rather than exact.

The restarts the control plane causes itself are no longer this poll's to
catch: every change it asks an agent for records the counters around it (see
`usage.counters`). What is left here is everything else -- a crash, a reboot,
an agent upgrade -- and the traffic of people who stay connected.
"""

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import select

from nebula_api.agent_client.client import AgentClient, AgentClientError
from nebula_api.db.engine import SessionFactory
from nebula_api.models.topology import ProtocolProfile, ServerProtocolCapability, VPNServer
from nebula_api.models.types import RUNNING_SERVER_STATES, CapabilityState, ServerState
from nebula_api.usage.counters import Clock, read_counters
from nebula_api.usage.service import UsageSample, UsageService

_LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class UsagePollSummary:
    servers_polled: int
    servers_failed: int
    samples: int
    credentials_active: int
    sources_failed: list[str]
    # Servers whose agent reached its relay's exit (the "relay" source).
    relay_checked: set[str] = field(default_factory=set)
    # Servers whose resolver answered (the "dns" source).
    resolver_checked: set[str] = field(default_factory=set)

    @property
    def had_problems(self) -> bool:
        return bool(self.servers_failed or self.sources_failed)


async def run_usage_poll(
    session_factory: SessionFactory,
    agent_client_builder: object,
    usage: UsageService,
    *,
    clock: Clock = lambda: datetime.now(UTC),
    relay_vias: frozenset[str] = frozenset(),
) -> UsagePollSummary:
    """[relay_vias]: servers some relay forwards through. One of them that is
    disabled (a relay only, no exit) is still asked, for its relay check
    alone: its counters and failures are no longer this poll's business."""
    async with session_factory() as session:
        servers = (
            await session.scalars(
                select(VPNServer).where(
                    VPNServer.state.in_(RUNNING_SERVER_STATES)
                    | (
                        (VPNServer.state == ServerState.DISABLED.value)
                        & VPNServer.code.in_(sorted(relay_vias))
                    )
                )
            )
        ).all()

    polled = 0
    failed = 0
    collected: list[UsageSample] = []
    sources_failed: list[str] = []
    relay_checked: set[str] = set()
    resolver_checked: set[str] = set()
    served: dict[object, frozenset[str]] = {}

    for server in servers:
        client_factory = agent_client_builder
        client: AgentClient = client_factory(server.agent_host, server.agent_port)  # type: ignore[operator]
        try:
            async with client:
                reading = await read_counters(client, clock=clock)
        except (AgentClientError, OSError) as error:
            # An unreachable server means its counters keep running and the
            # next successful poll still carries the total, so this is a
            # delay rather than a loss. Worth counting, not worth aborting
            # the other servers for.
            _LOGGER.warning("usage poll failed for %s: %s", server.code, str(error)[:200])
            failed += 1
            continue

        polled += 1
        if server.state == ServerState.DISABLED.value:
            if "relay" in reading.sources_read:
                relay_checked.add(server.code)
            continue
        sources_failed.extend(f"{server.code}:{name}" for name in reading.sources_failed)
        collected.extend(reading.samples)
        if reading.served_profiles:
            served[server.id] = reading.served_profiles
        if "relay" in reading.sources_read:
            relay_checked.add(server.code)
        if "dns" in reading.sources_read:
            resolver_checked.add(server.code)

    active = await usage.record(collected)
    if served:
        await offer_served_profiles(session_factory, served)
    return UsagePollSummary(
        servers_polled=polled,
        servers_failed=failed,
        samples=len(collected),
        credentials_active=active,
        sources_failed=sources_failed,
        relay_checked=relay_checked,
        resolver_checked=resolver_checked,
    )


async def offer_served_profiles(
    session_factory: SessionFactory, served: dict[object, frozenset[str]]
) -> int:
    """Offers what each server says it serves (and each one's ad-block twin,
    the same inbound) where the control plane has no row for it yet: a
    protocol turned on on a server then reaches its users without anyone
    running a command here. A row that exists is left as it is, so a protocol
    an administrator turned off stays off.

    ponytail: adds only. A protocol turned off on the server stays offered
    until it is turned off here too; removing on the server's word needs every
    agent to report every profile it serves (the DNS tunnel's does not yet).
    """

    added = 0
    async with session_factory() as session:
        for server_id, codes in served.items():
            wanted = set(codes) | {f"{code}-adblock" for code in codes}
            have = set(
                (
                    await session.scalars(
                        select(ServerProtocolCapability.protocol_profile_id).where(
                            ServerProtocolCapability.vpn_server_id == server_id
                        )
                    )
                ).all()
            )
            for profile in (
                await session.scalars(
                    select(ProtocolProfile).where(ProtocolProfile.code.in_(wanted))
                )
            ).all():
                if profile.id in have:
                    continue
                session.add(
                    ServerProtocolCapability(
                        vpn_server_id=server_id,
                        protocol_profile_id=profile.id,
                        state=CapabilityState.ENABLED.value,
                        validated_profile_version=str(profile.version),
                    )
                )
                added += 1
                _LOGGER.info("offering %s on server %s: it serves it", profile.code, server_id)
        await session.commit()
    return added
