"""Subscription links: an account's servers for other apps (iOS above all).

Streisand, V2Box, Hiddify, FoXray and v2rayNG read a URL that answers with
base64 share links, one per line, plus a `subscription-userinfo` header they
show as a usage bar. Nebula has no iOS app (it needs a paid Apple account),
so this is how an iPhone or iPad uses a Nebula account.

A link is a device of the account (platform "ios", see
UserAuthService.new_subscription): its credentials are its own, it counts
against the device limit, and revoking it under Devices ends the link.
"""

import base64
import json
import time
from typing import Annotated, cast
from urllib.parse import quote, urlencode
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from nebula_api.account.service import AccountService
from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.auth.redis_state import AuthStateUnavailable
from nebula_api.auth.user_authorization import require_user_session
from nebula_api.auth.user_service import (
    AuthenticatedUser,
    AuthenticationRejected,
    DeviceLimitReached,
    UserAuthService,
)
from nebula_api.devices.routes import xray_client_for
from nebula_api.devices.schemas import XrayClientResponse
from nebula_api.provisioning.service import ProvisioningError
from nebula_api.relays import relays_up, with_relays
from nebula_api.servers.service import ServerDiscoveryService
from nebula_api.topology_seed import WIREGUARD_PROTOCOL_CODE

router = APIRouter(tags=["subscription"])

# Not something a share link can carry: it needs the app's own engine.
_SKIPPED_PROFILES = frozenset({"vless-enc-dns"})
# Apps fetch every few hours, and each fetch asks for one credential per
# protocol, against the account's 100 provisioning requests per 15 minutes.
# ponytail: per process, so each API worker keeps its own; Redis if it runs several.
_CACHE_SECONDS = 15 * 60
_cache: dict[UUID, tuple[float, str]] = {}


def _service[T](request: Request, name: str, kind: type[T]) -> T:
    service = getattr(request.app.state, name, None)
    if service is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE)
    return cast(T, service)


@router.post("/v1/account/subscription")
async def new_subscription(
    request: Request,
    response: Response,
    principal: Annotated[AuthenticatedUser, Depends(require_user_session)],
) -> dict[str, str]:
    """A new link; the account's previous one stops working."""

    try:
        secret = await _service(request, "user_auth_service", UserAuthService).new_subscription(
            user_id=principal.user_id, request_id=uuid4()
        )
    except DeviceLimitReached as error:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="device_limit_reached"
        ) from error
    except AuthenticationRejected as error:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN) from error
    apply_auth_response_headers(response)
    # A path: the app puts it after whichever address it reaches the API on.
    return {"path": f"/v1/sub/{secret}"}


@router.get("/v1/sub/{secret}")
async def subscription(secret: str, request: Request) -> Response:
    owner = await _service(request, "user_auth_service", UserAuthService).subscription_owner(secret)
    if owner is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    user_id, device_id = owner
    account = await _service(request, "account_service", AccountService).get_account(user_id)
    if account is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    cached = _cache.get(device_id)
    if cached is not None and cached[0] > time.monotonic():
        body = cached[1]
    else:
        body = base64.b64encode(
            "\n".join(await _links(request, user_id, device_id)).encode()
        ).decode()
        _cache[device_id] = (time.monotonic() + _CACHE_SECONDS, body)

    expire = int(account.expires_at.timestamp()) if account.expires_at else 0
    return Response(
        content=body,
        media_type="text/plain",
        headers={
            # The usage bar: these apps all read this panel header.
            "subscription-userinfo": (
                f"upload=0; download={account.used_bytes}; "
                f"total={account.quota_bytes or 0}; expire={expire}"
            ),
            "profile-title": "base64:" + base64.b64encode(b"Nebula").decode(),
            "profile-update-interval": "6",
            "cache-control": "no-store",
        },
    )


async def _links(request: Request, user_id: UUID, device_id: UUID) -> list[str]:
    servers = await _service(
        request, "server_discovery_service", ServerDiscoveryService
    ).list_available_servers(user_id, include_maintenance=False)
    relays = request.app.state.settings.relay_list()
    if relays:
        servers = with_relays(
            servers, relays, await relays_up(request, relays), include_maintenance=False
        )
    links: list[str] = []
    for server in servers:
        for profile in server.profiles:
            if (
                profile.protocol_code == WIREGUARD_PROTOCOL_CODE
                or profile.code in _SKIPPED_PROFILES
            ):
                continue
            try:
                credential = await xray_client_for(
                    request,
                    user_id=user_id,
                    device_id=device_id,
                    server_code=server.code,
                    protocol_profile_code=profile.code,
                )
            except (ProvisioningError, AuthStateUnavailable, HTTPException):
                # One profile that cannot be had leaves the others listed.
                continue
            link = share_link(credential, f"{server.display_name} | {profile.display_name}")
            if link is not None:
                links.append(link)
    return links


def share_link(c: XrayClientResponse, name: str) -> str | None:
    """[c] as the share link other clients import; None for a kind they lack."""

    fragment = "#" + quote(name, safe="")
    host = f"[{c.server_address}]" if ":" in c.server_address else c.server_address
    if c.transport == "hysteria":
        hysteria = {"sni": c.sni}
        if c.obfs_password:
            hysteria |= {"obfs": "salamander", "obfs-password": c.obfs_password}
        if c.port_hop:
            hysteria["mport"] = c.port_hop
        auth = quote(str(c.uuid), safe="")
        return f"hysteria2://{auth}@{host}:{c.port}/?{urlencode(hysteria)}{fragment}"
    if c.protocol == "shadowsocks":
        user = base64.urlsafe_b64encode(f"{c.method}:{c.password}".encode()).decode().rstrip("=")
        return f"ss://{user}@{host}:{c.port}{fragment}"
    network = {"raw": "tcp", "websocket": "ws"}.get(c.transport, c.transport)
    if c.protocol == "vmess":
        return (
            "vmess://"
            + base64.b64encode(
                json.dumps(
                    {
                        "v": "2",
                        "ps": name,
                        "add": c.server_address,
                        "port": str(c.port),
                        "id": str(c.uuid),
                        "aid": "0",
                        "scy": "auto",
                        "net": network,
                        "type": "none",
                        "host": c.sni if network == "ws" else "",
                        "path": c.path or "",
                        "tls": "tls" if c.transport_security == "tls" else "",
                        "sni": c.sni if c.transport_security == "tls" else "",
                    },
                    separators=(",", ":"),
                ).encode()
            ).decode()
        )
    if c.protocol not in ("vless", "trojan"):
        return None
    query: dict[str, str] = {"type": network, "security": c.transport_security}
    if c.protocol == "vless":
        query["encryption"] = c.encryption or "none"
    if c.transport_security in ("tls", "reality"):
        query |= {"sni": c.sni, "fp": "chrome"}
    if c.transport_security == "reality":
        query |= {"pbk": c.reality_public_key or "", "sid": c.reality_short_id or ""}
    if c.ech_config_list:
        query["ech"] = c.ech_config_list
    if c.flow:
        query["flow"] = c.flow
    if network in ("ws", "xhttp"):
        query["path"] = c.path or "/"
        query["host"] = c.sni
    if network == "grpc":
        query |= {"serviceName": c.service_name or "", "mode": "gun"}
    secret = quote((c.password if c.protocol == "trojan" else str(c.uuid)) or "", safe="")
    return f"{c.protocol}://{secret}@{host}:{c.port}?{urlencode(query)}{fragment}"
