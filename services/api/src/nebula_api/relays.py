"""Relays: a server that forwards some of its ports to another (the exit).

The app lists a relay as a server of its own ("Germany via Tehran") with the
exit's profiles it forwards, at the relay's address and ports. A credential
asked for it is the device's credential on the exit -- the same one the exit
entry hands out -- so device limits, usage and revocation stay the exit's. It
comes back with the relay's address and port; TLS still names the exit, whose
certificate the app checks. Configured with NEBULA_RELAYS; see
docs/runbooks/relay.md.

The relay's own agent checks that the exit's forwarded ports answer from
there, reported as the usage source "relay"; and the relay's server reports
in itself (POST /v1/relays/{code}/up). Either keeps it up for
RELAY_UP_SECONDS; with neither it is listed as under maintenance, rather than
failing to connect without a reason. The report exists because Iran filters
TLS into Iranian servers from abroad at times (2026-11-11, from 16:00 UTC):
the poll from the exit could not reach the relay's agent while the relay,
which only needs the outward way, kept working.
"""

import hmac
from collections.abc import Iterable
from dataclasses import replace
from typing import Protocol, Self

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, model_validator

from nebula_api.servers.service import AvailableServerEntry

_CODE = r"^[a-z0-9][a-z0-9_-]{0,63}$"
RELAY_UP_SECONDS = 90


def base_profile(code: str) -> str:
    """The profile an "-adblock" sibling shares its port with."""
    return code.removesuffix("-adblock")


class Relay(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    code: str = Field(pattern=_CODE)
    display_name: str = Field(min_length=1, max_length=96)
    # The server the traffic leaves from, and the one forwarding to it.
    exit: str = Field(pattern=_CODE)
    via: str = Field(pattern=_CODE)
    # The relay's public address, and the port it forwards for each of the
    # exit's profiles (codes without "-adblock").
    host: str = Field(min_length=1, max_length=253, pattern=r"^[A-Za-z0-9.:-]+$")
    ports: dict[str, int] = Field(min_length=1)

    @model_validator(mode="after")
    def check(self) -> Self:
        if self.code in (self.exit, self.via):
            raise ValueError("a relay's code must differ from its exit and via servers")
        for profile, port in self.ports.items():
            if not 1 <= port <= 65535 or profile != base_profile(profile):
                raise ValueError(f"relay port for {profile!r} must be 1-65535, no -adblock")
        return self

    def port_for(self, profile_code: str) -> int | None:
        return self.ports.get(base_profile(profile_code))


def parse_relays(raw: str) -> tuple[Relay, ...]:
    if not raw.strip():
        return ()
    relays = TypeAdapter(list[Relay]).validate_json(raw)
    codes = [relay.code for relay in relays]
    if len(codes) != len(set(codes)):
        raise ValueError("relay codes must be unique")
    return tuple(relays)


def find_relay(relays: Iterable[Relay], server_code: str) -> Relay | None:
    return next((relay for relay in relays if relay.code == server_code), None)


def with_relays(
    entries: list[AvailableServerEntry],
    relays: Iterable[Relay],
    up: set[str],
    *,
    include_maintenance: bool,
) -> list[AvailableServerEntry]:
    """[entries] plus each relay whose exit the account may use."""
    by_code = {entry.code: entry for entry in entries}
    listed = list(entries)
    for relay in relays:
        exit_entry = by_code.get(relay.exit)
        if exit_entry is None:
            continue
        maintenance = exit_entry.maintenance or relay.code not in up
        if maintenance and not include_maintenance:
            continue
        # In the order NEBULA_RELAYS lists them, so the best through this
        # relay comes first; a profile left out of it is not offered.
        order = list(relay.ports)
        profiles = sorted(
            (
                # transport=None: never moved onto the CDN route's port.
                replace(profile, required_port=port, transport=None)
                for profile in exit_entry.profiles
                if profile.protocol_code != "wireguard"
                and (port := relay.port_for(profile.code)) is not None
            ),
            key=lambda profile: (order.index(base_profile(profile.code)), profile.code),
        )
        if profiles:
            listed.append(
                AvailableServerEntry(
                    code=relay.code,
                    display_name=relay.display_name,
                    public_host=relay.host,
                    profiles=profiles,
                    maintenance=maintenance,
                )
            )
    return listed


class _Redis(Protocol):
    async def mget(self, keys: list[str]) -> list[object]: ...
    async def set(self, name: str, value: str, ex: int) -> object: ...


def _key(code: str) -> str:
    return f"nebula:relay-up:{code}"


class RelayHealth:
    def __init__(self, redis: _Redis) -> None:
        self._redis = redis

    async def up(self, relays: Iterable[Relay]) -> set[str]:
        codes = [relay.code for relay in relays]
        if not codes:
            return set()
        values = await self._redis.mget([_key(code) for code in codes])
        return {code for code, value in zip(codes, values, strict=True) if value is not None}

    async def record(self, relays: Iterable[Relay], checked: set[str]) -> None:
        """[checked]: the servers whose agent reached its relay's exit.

        Only ever marks up: a poll that could not reach the relay says nothing
        the relay's own report may not have said since, and the mark expires
        by itself.
        """
        for relay in relays:
            if relay.via in checked:
                await self.mark_up(relay.code)

    async def mark_up(self, code: str) -> None:
        await self._redis.set(_key(code), "1", ex=RELAY_UP_SECONDS)


async def relays_up(request: Request, relays: tuple[Relay, ...]) -> set[str]:
    # No health store (no Redis): no relay is known to work, so none is offered.
    health: RelayHealth | None = getattr(request.app.state, "relay_health", None)
    return await health.up(relays) if health is not None and relays else set()


def with_relay_codes(server_codes: list[str], relays: Iterable[Relay]) -> list[str]:
    """A device holding a credential on an exit holds it for its relays too.

    The app ends a tunnel whose server is not among its device's codes.
    """
    return sorted({*server_codes, *(r.code for r in relays if r.exit in server_codes)})


router = APIRouter(tags=["relays"])


@router.post("/v1/relays/{code}/up", status_code=status.HTTP_204_NO_CONTENT)
async def relay_reports_up(code: str, request: Request) -> Response:
    """A relay's server saying it reaches its exit: the request itself is the
    proof, made the way the relay's traffic goes (from Iran outward).

    The shared token (NEBULA_RELAY_REPORT_TOKEN) is the credential. Without
    one configured, or for a code that is not a relay, nothing is recorded
    and the answer is 404, so the route says nothing about the deployment.
    """
    settings = request.app.state.settings
    expected = settings.relay_report_token.get_secret_value()
    given = request.headers.get("authorization", "").removeprefix("Bearer ")
    relay = find_relay(settings.relay_list(), code)
    health: RelayHealth | None = getattr(request.app.state, "relay_health", None)
    if (
        not expected
        or not hmac.compare_digest(given.encode(), expected.encode())
        or relay is None
        or health is None
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    await health.mark_up(relay.code)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
