"""The deployment's DNS records in the admin panel: every one it needs and
whether the public DNS has it right (dns_records.py)."""

from typing import cast

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel

from nebula_api.auth.admin_authorization import require_admin_session
from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.db.engine import SessionFactory
from nebula_api.dns_records import check, needed, servers
from nebula_api.dns_tunnels import list_tunnels
from nebula_api.settings import Settings

router = APIRouter(prefix="/v1/admin/dns-records", tags=["admin-dns-records"])


class RecordStatusItem(BaseModel):
    name: str
    type: str
    value: str
    purpose: str
    proxied: bool
    ok: bool
    found: list[str]
    detail: str


class RecordsResponse(BaseModel):
    items: list[RecordStatusItem]


@router.get("", response_model=RecordsResponse)
async def list_dns_records(request: Request, response: Response) -> RecordsResponse:
    """Looked up live, one name at a time: a few seconds."""

    await require_admin_session(request)
    sessions = getattr(request.app.state, "dns_tunnel_sessions", None)
    if sessions is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE)
    sessions = cast(SessionFactory, sessions)
    settings = cast(Settings, request.app.state.settings)
    statuses = await check(needed(settings, await servers(sessions), await list_tunnels(sessions)))
    apply_auth_response_headers(response)
    return RecordsResponse(
        items=[
            RecordStatusItem(
                name=s.record.name,
                type=s.record.type,
                value=s.record.value,
                purpose=s.record.purpose,
                proxied=s.record.proxied,
                ok=s.ok,
                found=s.found,
                detail=s.detail,
            )
            for s in statuses
        ]
    )
