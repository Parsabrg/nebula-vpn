"""DNS tunnels in the admin panel: each server's names, the DNS records they
need at the DNS provider, and whether those work (dns_tunnels.py)."""

from typing import cast
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, Field

from nebula_api.agent_client.client import AgentClientBuilder
from nebula_api.auth.admin_authorization import authorize_admin_mutation, require_admin_session
from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.db.engine import SessionFactory
from nebula_api.dns_tunnels import check, clean_names, list_tunnels, push, records, set_tunnel
from nebula_api.models.types import AdminRole

router = APIRouter(prefix="/v1/admin/dns-tunnels", tags=["admin-dns-tunnels"])
_MUTATION_ROLES = frozenset({AdminRole.OWNER, AdminRole.OPERATOR})


class TunnelItem(BaseModel):
    server_id: UUID
    server_code: str
    domains: list[str]


class TunnelListResponse(BaseModel):
    items: list[TunnelItem]


class SetTunnelRequest(BaseModel):
    # None or empty: no tunnel on this server.
    domains: list[str] = Field(default_factory=list, max_length=8)


class SetTunnelResponse(TunnelItem):
    # False when the server's agent could not be told now; the reconcile
    # sweep tells it again within 15 minutes.
    applied: bool


class RecordItem(BaseModel):
    name: str
    type: str
    value: str


class CheckItem(BaseModel):
    key: str
    ok: bool
    detail: str


class CheckResponse(BaseModel):
    server_ip: str | None
    records: list[RecordItem]
    checks: list[CheckItem]


def _sessions(request: Request) -> SessionFactory:
    sessions = getattr(request.app.state, "dns_tunnel_sessions", None)
    if sessions is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE)
    return cast(SessionFactory, sessions)


@router.get("", response_model=TunnelListResponse)
async def list_dns_tunnels(request: Request, response: Response) -> TunnelListResponse:
    await require_admin_session(request)
    entries = await list_tunnels(_sessions(request))
    apply_auth_response_headers(response)
    return TunnelListResponse(
        items=[
            TunnelItem(server_id=e.server_id, server_code=e.server_code, domains=e.domains)
            for e in entries
        ]
    )


@router.post("/{server_id}", response_model=SetTunnelResponse)
async def set_dns_tunnel(
    server_id: UUID, payload: SetTunnelRequest, request: Request, response: Response
) -> SetTunnelResponse:
    """Step-up: it opens a way into the server (still behind a credential)."""

    try:
        domains = clean_names(payload.domains)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(error)
        ) from error
    principal = await authorize_admin_mutation(
        request, allowed_roles=_MUTATION_ROLES, require_step_up=True
    )
    sessions = _sessions(request)
    taken = {
        name for e in await list_tunnels(sessions) if e.server_id != server_id for name in e.domains
    }
    if taken & set(domains):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="name_on_another_server")
    entry = await set_tunnel(
        sessions, server_id=server_id, domains=domains, admin_id=principal.admin_id
    )
    if entry is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Server not found")
    agents: AgentClientBuilder | None = getattr(request.app.state, "dns_tunnel_agents", None)
    applied = agents is not None and await push(sessions, agents, server_id)
    apply_auth_response_headers(response)
    return SetTunnelResponse(
        server_id=entry.server_id,
        server_code=entry.server_code,
        domains=entry.domains,
        applied=applied,
    )


@router.get("/{server_id}/check", response_model=CheckResponse)
async def check_dns_tunnel(server_id: UUID, request: Request, response: Response) -> CheckResponse:
    """The records the DNS provider needs, and whether the first name works."""

    await require_admin_session(request)
    entry = next(
        (e for e in await list_tunnels(_sessions(request)) if e.server_id == server_id), None
    )
    if entry is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No DNS tunnel")
    server_ip, checks = await check(entry.domains[0], entry.public_host)
    apply_auth_response_headers(response)
    return CheckResponse(
        server_ip=server_ip,
        records=[
            RecordItem(name=n, type=t, value=v)
            for name in entry.domains
            for n, t, v in records(name, server_ip or "<this server's address>")
        ],
        checks=[CheckItem(key=c.key, ok=c.ok, detail=c.detail) for c in checks],
    )
