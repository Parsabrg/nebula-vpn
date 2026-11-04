"""DNS profiles (roadmap 13; 108 D27-D29): the resolver a tunnel is given.

An account has one; a device may override it. Handed to Xray clients as
`client_dns`, which the app puts in the tunnel's DNS settings. An ad-blocking
protocol profile still uses its own filtering resolver -- the app decides
that -- so "ads" here is for the plain profiles.
"""

from typing import Literal, Protocol

from fastapi import Request

DnsProfile = Literal["default", "ads", "family"]
DNS_PROFILES: tuple[DnsProfile, ...] = ("default", "ads", "family")

# AdGuard DNS: its filtering resolver blocks ads and trackers; its family one
# also blocks adult sites and enforces safe search. Reached through the
# tunnel, from the server, like any other address.
_PUBLIC: dict[str, list[str]] = {
    "ads": ["94.140.14.14", "94.140.15.15"],
    "family": ["94.140.14.15", "94.140.15.16"],
}


def resolvers_for(profile: str, deployment_dns: str) -> list[str]:
    """The `client_dns` list: the deployment's own resolver for "default"
    (empty when it runs none, so the app keeps its own), a public filtering
    one otherwise."""

    if profile in _PUBLIC:
        return list(_PUBLIC[profile])
    return [deployment_dns] if deployment_dns else []


def effective_profile(user_profile: str, device_profile: str | None) -> str:
    return device_profile or user_profile


# Which servers' resolvers answered the latest usage poll (the agent's "dns"
# source). The deployment's own resolver address is handed out only for
# those: on a server without one, every lookup through it was blackholed.
# ponytail: a resolver that dies stays "up" until its mark expires (90 s).
RESOLVER_UP_SECONDS = 90


class _Redis(Protocol):
    async def mget(self, keys: list[str]) -> list[object]: ...
    async def set(self, name: str, value: str, ex: int) -> object: ...


def _key(server_code: str) -> str:
    return f"nebula:resolver-up:{server_code}"


class ResolverHealth:
    def __init__(self, redis: _Redis) -> None:
        self._redis = redis

    async def record(self, checked: set[str]) -> None:
        for code in checked:
            await self._redis.set(_key(code), "1", ex=RESOLVER_UP_SECONDS)

    async def is_up(self, server_code: str) -> bool:
        return (await self._redis.mget([_key(server_code)]))[0] is not None


async def deployment_dns_for(request: Request, server_code: str) -> str:
    """The deployment's resolver address, or "" where it does not answer."""
    address: str = request.app.state.settings.xray_client_dns
    health: ResolverHealth | None = getattr(request.app.state, "resolver_health", None)
    if not address or health is None:
        return ""
    return address if await health.is_up(server_code) else ""
