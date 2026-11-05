"""The DNS tunnel's details for signed-in apps (plan 10; ADR 0004, 2026-11-05).

An app asks while the API is reachable and keeps the answer: in a shutdown,
when only DNS still gets out, there is no API to ask. The tunnel forwards to
one server's VLESS Encryption inbound, so the app still needs its credential
there (`server_code`); the key alone reaches nothing.
"""

from pathlib import Path
from typing import Annotated, cast

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.auth.schemas import AuthModel
from nebula_api.auth.user_authorization import require_user_session
from nebula_api.auth.user_service import AuthenticatedUser
from nebula_api.settings import Settings

router = APIRouter(prefix="/v1/dns-tunnel", tags=["dns-tunnel"])

# AES-256-GCM, the only method the server accepts (ENCRYPTION_AUTO_DETECT off).
ENCRYPTION_METHOD = 5


class DnsTunnelResponse(AuthModel):
    # Tried in turn: a second name on another domain needs no app update.
    domains: list[str]
    key: str
    encryption_method: int
    server_code: str


@router.get("/", response_model=DnsTunnelResponse)
def dns_tunnel(
    request: Request,
    response: Response,
    principal: Annotated[AuthenticatedUser, Depends(require_user_session)],
) -> DnsTunnelResponse:
    del principal  # Any signed-in account; the credential behind it decides.
    settings = cast(Settings, request.app.state.settings)
    key = ""
    domains = [name.strip() for name in settings.dns_tunnel_domains.split(",") if name.strip()]
    if domains and settings.dns_tunnel_server:
        try:
            key = Path(settings.dns_tunnel_key_file).read_text(encoding="utf-8").strip()
        except OSError:
            key = ""
    if not key:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No DNS tunnel")
    apply_auth_response_headers(response)
    return DnsTunnelResponse(
        domains=domains,
        key=key,
        encryption_method=ENCRYPTION_METHOD,
        server_code=settings.dns_tunnel_server,
    )
