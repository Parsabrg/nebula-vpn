"""Relays in the admin panel: list them (from NEBULA_RELAYS and the panel)
with whether each is up, and add or remove those kept in the panel.

The relay's own server still needs its forwarding set up from a shell
(install.sh with relay.env); the list carries what that setup needs, so the
panel can show the commands. See docs/runbooks/relay.md.
"""

import re
from typing import cast
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from nebula_api.auth.admin_authorization import authorize_admin_mutation, require_admin_session
from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.models.types import AdminRole
from nebula_api.relays import Relay, RelayCatalog, RelayHealth, base_profile, relay_list
from nebula_api.topology_admin.service import TopologyAdminService

router = APIRouter(prefix="/v1/admin/relays", tags=["admin-relays"])
_MUTATION_ROLES = frozenset({AdminRole.OWNER, AdminRole.OPERATOR})


class RelayPortItem(BaseModel):
    profile_code: str
    port: int
    # Where the profile listens on the exit, and over what: the relay's
    # forwarding rule (relay.env NEBULA_RELAY_PORTS) is built from these.
    exit_port: int | None
    udp: bool


class RelayItem(BaseModel):
    code: str
    display_name: str
    exit_code: str
    exit_name: str
    exit_host: str
    via_code: str
    via_name: str
    host: str
    ports: list[RelayPortItem]
    # "settings" (NEBULA_RELAYS, changed on the server) or "panel".
    source: str
    up: bool


class RelayListResponse(BaseModel):
    items: list[RelayItem]
    # Where a relay's server reports in (POST {report_url}/v1/relays/{code}/up):
    # the CDN's name when there is one -- from Iran it answered when the
    # server's own name did not (2026-11-11) -- else the API's.
    report_url: str


class AddRelayRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str = Field(min_length=1, max_length=96)
    exit_server_id: UUID
    via_server_id: UUID
    host: str = Field(min_length=1, max_length=253)
    ports: dict[str, int] = Field(min_length=1)


def _service(request: Request) -> TopologyAdminService:
    service = getattr(request.app.state, "topology_admin_service", None)
    if service is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE)
    return cast(TopologyAdminService, service)


@router.get("", response_model=RelayListResponse)
async def list_relays(request: Request, response: Response) -> RelayListResponse:
    await require_admin_session(request)
    relays = await relay_list(request)
    configured = {relay.code for relay in request.app.state.settings.relay_list()}
    servers, profiles = await _service(request).relay_context()
    health: RelayHealth | None = getattr(request.app.state, "relay_health", None)
    up = await health.up(relays) if health is not None else set()
    apply_auth_response_headers(response)

    def item(relay: Relay) -> RelayItem:
        exit_ = servers.get(relay.exit)
        via = servers.get(relay.via)
        return RelayItem(
            code=relay.code,
            display_name=relay.display_name,
            exit_code=relay.exit,
            exit_name=exit_[1] if exit_ else relay.exit,
            exit_host=exit_[2] if exit_ else "",
            via_code=relay.via,
            via_name=via[1] if via else relay.via,
            host=relay.host,
            ports=[
                RelayPortItem(
                    profile_code=code,
                    port=port,
                    exit_port=profiles[code].port if code in profiles else None,
                    udp=profiles[code].udp if code in profiles else False,
                )
                for code, port in relay.ports.items()
            ],
            source="settings" if relay.code in configured else "panel",
            up=relay.code in up,
        )

    settings = request.app.state.settings
    cdns = [name.strip() for name in settings.cdn_host.split(",") if name.strip()]
    report_url = f"https://{cdns[0]}" if cdns else settings.api_public_url.rstrip("/")
    return RelayListResponse(items=[item(relay) for relay in relays], report_url=report_url)


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
async def add_relay(payload: AddRelayRequest, request: Request, response: Response) -> Response:
    """Step-up: it decides a route people's traffic takes."""

    principal = await authorize_admin_mutation(
        request, allowed_roles=_MUTATION_ROLES, require_step_up=True
    )
    servers, _ = await _service(request).relay_context()
    by_id = {server_id: code for code, (server_id, _, _) in servers.items()}
    exit_code = by_id.get(payload.exit_server_id)
    via_code = by_id.get(payload.via_server_id)
    if exit_code is None or via_code is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Server not found")
    code = re.sub(r"[^a-z0-9_-]", "-", f"{exit_code}-via-{via_code}".lower())[:64]
    try:
        relay = Relay(
            code=code,
            display_name=payload.display_name.strip(),
            exit=exit_code,
            via=via_code,
            host=payload.host.strip(),
            ports={base_profile(p): port for p, port in payload.ports.items()},
        )
    except ValidationError as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Check the relay's fields"
        ) from error
    if any(existing.code == code for existing in await relay_list(request)):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="relay_exists")
    try:
        await _service(request).add_relay(
            code=relay.code,
            display_name=relay.display_name,
            exit_server_id=payload.exit_server_id,
            via_server_id=payload.via_server_id,
            host=relay.host,
            ports=relay.ports,
            admin_id=principal.admin_id,
            request_id=uuid4(),
        )
    except LookupError as error:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND) from error
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="relay_exists") from error
    _forget(request)
    apply_auth_response_headers(response)
    return Response(status_code=status.HTTP_204_NO_CONTENT, headers=dict(response.headers))


@router.post("/{code}/delete", status_code=status.HTTP_204_NO_CONTENT)
async def remove_relay(code: str, request: Request, response: Response) -> Response:
    principal = await authorize_admin_mutation(
        request, allowed_roles=_MUTATION_ROLES, require_step_up=True
    )
    if any(relay.code == code for relay in request.app.state.settings.relay_list()):
        # Kept in NEBULA_RELAYS: changed on the server, not here.
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="relay_in_settings")
    removed = await _service(request).remove_relay(
        code=code, admin_id=principal.admin_id, request_id=uuid4()
    )
    if not removed:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Relay not found")
    _forget(request)
    apply_auth_response_headers(response)
    return Response(status_code=status.HTTP_204_NO_CONTENT, headers=dict(response.headers))


def _forget(request: Request) -> None:
    catalog: RelayCatalog | None = getattr(request.app.state, "relay_catalog", None)
    if catalog is not None:
        catalog.forget()
