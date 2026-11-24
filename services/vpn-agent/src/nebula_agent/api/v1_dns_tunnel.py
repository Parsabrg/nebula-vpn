"""The DNS tunnel this server should serve, from the control plane.

Desired state, not an operation: the same request twice changes nothing, so
it needs no idempotency ledger. No names means "no tunnel here". The control
plane sends it when an administrator changes it and again at every reconcile
sweep, so a rebuilt server or a missed push catches up by itself.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, Field

from nebula_agent.api._dispatch import enforce_body_size_limit
from nebula_agent.drivers.cottendns import apply_cottendns
from nebula_agent.settings import Settings

router = APIRouter(prefix="/v1/dns-tunnel", tags=["dns-tunnel"])

_NAME = r"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$"


class SetDnsTunnelRequest(BaseModel):
    domains: list[Annotated[str, Field(max_length=253, pattern=_NAME)]] = Field(
        default_factory=list, max_length=4
    )
    # AES-256-GCM's 32 characters; CottenDNS reads it as text.
    key: str = Field(default="", pattern=r"^$|^[0-9a-f]{32}$")


def _settings(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


@router.post(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(enforce_body_size_limit)],
)
async def set_dns_tunnel(
    payload: SetDnsTunnelRequest, settings: Annotated[Settings, Depends(_settings)]
) -> Response:
    if payload.domains and not payload.key:
        raise HTTPException(422, "a tunnel needs its key")
    if payload.domains and not settings.xray_vlessenc_enabled:
        # It forwards only to the VLESS Encryption inbound.
        raise HTTPException(status.HTTP_409_CONFLICT, "VLESS Encryption is off on this server")
    await apply_cottendns(settings, payload.domains, payload.key)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
