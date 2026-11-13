"""Which address subscription links name, chosen in the admin panel.

Automatic by default (a relay server in Iran while it is up, else the CDN);
an administrator can pin one of the offered addresses instead. Only offered
ones are accepted: a link naming any other host would send people's iPhone
apps to whoever holds it.
"""

from typing import cast
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field

from nebula_api.auth.admin_authorization import authorize_admin_mutation, require_admin_session
from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.models.types import AdminRole
from nebula_api.subscription import AUTOMATIC, SUBSCRIPTION_HOST, link_options
from nebula_api.topology_admin.service import TopologyAdminService

router = APIRouter(prefix="/v1/admin/subscription-link", tags=["admin-subscription-link"])


class LinkOption(BaseModel):
    value: str
    label: str


class LinkChoiceResponse(BaseModel):
    choice: str
    options: list[LinkOption]


class LinkChoiceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    choice: str = Field(min_length=1, max_length=260)


def _service(request: Request) -> TopologyAdminService:
    service = getattr(request.app.state, "topology_admin_service", None)
    if service is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE)
    return cast(TopologyAdminService, service)


@router.get("", response_model=LinkChoiceResponse)
async def get_link_choice(request: Request, response: Response) -> LinkChoiceResponse:
    await require_admin_session(request)
    chosen = await _service(request).choice(SUBSCRIPTION_HOST) or AUTOMATIC
    options = await link_options(request)
    apply_auth_response_headers(response)
    return LinkChoiceResponse(
        choice=chosen if chosen in (value for value, _ in options) else AUTOMATIC,
        options=[LinkOption(value=value, label=label) for value, label in options],
    )


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
async def set_link_choice(
    payload: LinkChoiceRequest, request: Request, response: Response
) -> Response:
    principal = await authorize_admin_mutation(
        request, allowed_roles=frozenset({AdminRole.OWNER, AdminRole.OPERATOR})
    )
    if payload.choice not in (value for value, _ in await link_options(request)):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Not an offered address"
        )
    await _service(request).choose(
        key=SUBSCRIPTION_HOST,
        value=payload.choice,
        admin_id=principal.admin_id,
        request_id=uuid4(),
    )
    apply_auth_response_headers(response)
    return Response(status_code=status.HTTP_204_NO_CONTENT, headers=dict(response.headers))
