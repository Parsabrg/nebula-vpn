"""The relay this server should be: written for root to apply.

A relay forwards some of this server's ports to an exit server, for apps
that reach this one and not the exit (docs/runbooks/relay.md). The control
plane says what it should be; this agent runs unprivileged and cannot change
the firewall, so it only writes the request to a file. A root unit
(nebula-relay.path, installed by install.sh) sees the file change, checks
every value again and applies it with the same script install.sh uses.

Desired state, not an operation: sending the same request twice changes
nothing, so it needs no idempotency ledger. No ports means "no relay".
"""

import os
import re
from ipaddress import IPv4Address
from pathlib import Path
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Request, Response, status
from pydantic import BaseModel, Field, field_validator

from nebula_agent.api._dispatch import enforce_body_size_limit
from nebula_agent.settings import Settings

router = APIRouter(prefix="/v1/relay", tags=["relay"])

# Never forwarded: the exit's SSH, certificate renewal, panel and agent.
_NOT_VPN_PORTS = frozenset({22, 80, 8444, 9443})
_REPORT_URL = re.compile(r"^https://[A-Za-z0-9.-]+(:[0-9]+)?/v1/relays/[a-z0-9_-]+/up$")
_REPORT_TOKEN = re.compile(r"^[A-Za-z0-9_-]{16,}$")


class RelayPort(BaseModel):
    here: int = Field(ge=1, le=65_535)
    proto: Literal["tcp", "udp"]
    there: int = Field(ge=1, le=65_535)

    @field_validator("there")
    @classmethod
    def _vpn_port(cls, value: int) -> int:
        if value in _NOT_VPN_PORTS:
            raise ValueError("not a VPN port")
        return value


class SetRelayRequest(BaseModel):
    target: IPv4Address | None = None
    ports: list[RelayPort] = Field(default_factory=list, max_length=32)
    report_url: str | None = Field(default=None, max_length=300)
    report_token: str | None = Field(default=None, max_length=200)

    @field_validator("report_url")
    @classmethod
    def _url(cls, value: str | None) -> str | None:
        if value is not None and not _REPORT_URL.match(value):
            raise ValueError("not a relay report URL")
        return value

    @field_validator("report_token")
    @classmethod
    def _token(cls, value: str | None) -> str | None:
        if value is not None and not _REPORT_TOKEN.match(value):
            raise ValueError("not a report token")
        return value


def relay_env(payload: SetRelayRequest) -> str:
    """The request as relay.env lines, empty for no relay."""

    if not payload.ports or payload.target is None:
        return ""
    lines = [
        f"NEBULA_RELAY_TARGET={payload.target}",
        "NEBULA_RELAY_PORTS=" + " ".join(f"{p.here}/{p.proto}:{p.there}" for p in payload.ports),
    ]
    if payload.report_url and payload.report_token:
        lines += [
            f"NEBULA_RELAY_REPORT_URL={payload.report_url}",
            f"NEBULA_RELAY_REPORT_TOKEN={payload.report_token}",
        ]
    return "\n".join(lines) + "\n"


def _settings(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


@router.post(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(enforce_body_size_limit)],
)
async def set_relay(
    payload: SetRelayRequest, settings: Annotated[Settings, Depends(_settings)]
) -> Response:
    path = Path(str(settings.relay_request_file))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    # The report token is in it: readable by root and this agent only.
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(relay_env(payload))
    temporary.replace(path)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
