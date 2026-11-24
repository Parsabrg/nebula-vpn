"""The DNS tunnels' details for signed-in apps.

An app asks while the API is reachable and keeps the answer: in a shutdown,
when only DNS still gets out, there is no API to ask. Each tunnel forwards to
its server's VLESS Encryption inbound, so the app still needs its credential
there (`server_code`); the key alone reaches nothing. Set per server in the
admin panel (dns_tunnels.py).
"""

from collections.abc import Awaitable, Callable
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.auth.schemas import AuthModel
from nebula_api.auth.user_authorization import require_user_session
from nebula_api.auth.user_service import AuthenticatedUser
from nebula_api.dns_tunnels import TunnelEntry

router = APIRouter(prefix="/v1/dns-tunnel", tags=["dns-tunnel"])

# AES-256-GCM, the only method the server accepts (ENCRYPTION_AUTO_DETECT off).
ENCRYPTION_METHOD = 5

TunnelSource = Callable[[], Awaitable[list[TunnelEntry]]]


class DnsTunnelItem(AuthModel):
    # Tried in turn: a second name on another domain needs no app update.
    domains: list[str]
    key: str
    encryption_method: int
    server_code: str


class DnsTunnelResponse(DnsTunnelItem):
    # The first tunnel above, for apps from before there could be several.
    tunnels: list[DnsTunnelItem]


@router.get("/", response_model=DnsTunnelResponse)
async def dns_tunnel(
    request: Request,
    response: Response,
    principal: Annotated[AuthenticatedUser, Depends(require_user_session)],
) -> DnsTunnelResponse:
    del principal  # Any signed-in account; the credential behind it decides.
    source: TunnelSource | None = getattr(request.app.state, "dns_tunnel_source", None)
    tunnels = [
        DnsTunnelItem(
            domains=entry.domains,
            key=entry.key,
            encryption_method=ENCRYPTION_METHOD,
            server_code=entry.server_code,
        )
        for entry in (await source() if source else [])
    ]
    if not tunnels:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No DNS tunnel")
    apply_auth_response_headers(response)
    return DnsTunnelResponse(**tunnels[0].model_dump(), tunnels=tunnels)
