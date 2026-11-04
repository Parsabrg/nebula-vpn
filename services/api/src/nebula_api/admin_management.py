"""Owners manage the other admins: invite, role, disable, sessions.

Before this, only `nebula-api seed-admin` could make an admin, and only the
first one. An owner cannot change their own role or disable themselves (their
own sign-in page covers their account), so a deployment always keeps at least
one active owner: the one acting.
"""

import secrets
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import NoReturn, cast
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from nebula_api.auth.admin_authorization import authorize_admin_mutation, require_admin_session
from nebula_api.auth.admin_service import AdminPrincipal
from nebula_api.auth.audit import add_audit_event
from nebula_api.auth.http import apply_auth_response_headers
from nebula_api.auth.redis_state import AdminSessionRecord, AuthStateUnavailable, RedisAuthState
from nebula_api.db.engine import SessionFactory
from nebula_api.identity import normalize_email, normalize_username
from nebula_api.models.identity import AdminTotpCredential, AdminUser
from nebula_api.models.types import AdminRole, AdminState
from nebula_api.passwords import hash_password_async

Clock = Callable[[], datetime]

_OWNER = frozenset({AdminRole.OWNER})
_GENERIC_DETAIL = "Request was not accepted"


class AdminManagementRejected(Exception):
    """Refused, with a message an owner can act on."""

    def __init__(self, message: str, *, status_code: int = status.HTTP_409_CONFLICT) -> None:
        super().__init__(message)
        self.status_code = status_code


@dataclass(frozen=True, slots=True)
class AdminSummary:
    admin_id: UUID
    email: str
    username: str | None
    role: AdminRole
    state: AdminState
    has_authenticator: bool
    created_at: datetime
    disabled_at: datetime | None


@dataclass(frozen=True, slots=True, repr=False)
class InvitedAdmin:
    admin: AdminSummary
    temporary_password: str

    def __repr__(self) -> str:
        return "InvitedAdmin(temporary_password=<redacted>)"


class AdminManagementService:
    def __init__(
        self,
        session_factory: SessionFactory,
        redis_state: RedisAuthState,
        *,
        clock: Clock = lambda: datetime.now(UTC),
    ) -> None:
        self._session_factory = session_factory
        self._redis = redis_state
        self._clock = clock

    async def list_admins(self) -> list[AdminSummary]:
        async with self._session_factory() as session:
            admins = list(
                (
                    await session.scalars(select(AdminUser).order_by(AdminUser.email_normalized))
                ).all()
            )
            enrolled = set(
                (
                    await session.scalars(
                        select(AdminTotpCredential.admin_user_id).where(
                            AdminTotpCredential.state == "active"
                        )
                    )
                ).all()
            )
        return [_summary(admin, admin.id in enrolled) for admin in admins]

    async def invite(
        self, *, actor_id: UUID, email: str, username: str | None, role: AdminRole
    ) -> InvitedAdmin:
        """A new admin with a one-time password; they set up an authenticator
        at their first sign-in, as the first admin did."""

        normalized_email = normalize_email(email)
        normalized_username = normalize_username(username) if username else None
        temporary_password = secrets.token_urlsafe(18)
        password_hash = await hash_password_async(temporary_password)
        async with self._session_factory() as session:
            clashes = [AdminUser.email_normalized == normalized_email]
            if normalized_username is not None:
                clashes.append(AdminUser.username_normalized == normalized_username)
            taken = await session.scalar(select(AdminUser.id).where(or_(*clashes)))
            if taken is not None:
                raise AdminManagementRejected("An admin with this email or username exists.")
            admin = AdminUser(
                email=email.strip(),
                email_normalized=normalized_email,
                username=username.strip() if username else None,
                username_normalized=normalized_username,
                password_hash=password_hash,
                role=role,
                state=AdminState.ACTIVE,
                # Set here: the database default would be unloaded after the
                # insert, and reading it in an async session fails.
                created_at=self._clock(),
            )
            session.add(admin)
            await session.flush()
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=actor_id,
                target_kind="admin",
                target_id=admin.id,
                event_code="identity_state_changed",
                outcome="succeeded",
                request_id=uuid4(),
                reason_code="admin_invited",
            )
            await session.commit()
            summary = _summary(admin, False)
        return InvitedAdmin(admin=summary, temporary_password=temporary_password)

    async def change_role(self, *, actor_id: UUID, admin_id: UUID, role: AdminRole) -> AdminSummary:
        async with self._session_factory() as session:
            admin = await self._other_admin(session, actor_id, admin_id)
            if admin.role != role:
                admin.role = role
                # A new role takes effect at once: no session keeps the old one.
                admin.sessions_valid_after = self._clock()
                add_audit_event(
                    session,
                    actor_kind="admin",
                    actor_id=actor_id,
                    target_kind="admin",
                    target_id=admin.id,
                    event_code="identity_state_changed",
                    outcome="succeeded",
                    request_id=uuid4(),
                    reason_code="admin_role_changed",
                )
            await session.commit()
            return await self._summary_in(session, admin)

    async def set_disabled(self, *, actor_id: UUID, admin_id: UUID, disabled: bool) -> AdminSummary:
        async with self._session_factory() as session:
            admin = await self._other_admin(session, actor_id, admin_id)
            wanted = AdminState.DISABLED if disabled else AdminState.ACTIVE
            if admin.state != wanted:
                now = self._clock()
                admin.state = wanted
                admin.disabled_at = now if disabled else None
                admin.sessions_valid_after = now
                add_audit_event(
                    session,
                    actor_kind="admin",
                    actor_id=actor_id,
                    target_kind="admin",
                    target_id=admin.id,
                    event_code="identity_state_changed",
                    outcome="succeeded",
                    request_id=uuid4(),
                    reason_code="admin_disabled" if disabled else "admin_reactivated",
                )
            await session.commit()
            return await self._summary_in(session, admin)

    async def sessions(self, admin_id: UUID) -> list[AdminSessionRecord]:
        async with self._session_factory() as session:
            admin = await session.get(AdminUser, admin_id)
            if admin is None:
                raise AdminManagementRejected(_GENERIC_DETAIL, status_code=404)
            valid_after = admin.sessions_valid_after
        records = await self._redis.list_admin_sessions(admin_id)
        # Sessions that sign-in no longer accepts are not shown as live.
        return [r for r in records if valid_after is None or r.created_at >= valid_after]

    async def end_session(self, *, actor_id: UUID, admin_id: UUID, session_id: UUID) -> None:
        if not await self._redis.revoke_admin_session_by_id(admin_id, session_id):
            raise AdminManagementRejected(
                "That session has already ended.", status_code=status.HTTP_404_NOT_FOUND
            )
        async with self._session_factory() as session:
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=actor_id,
                target_kind="admin",
                target_id=admin_id,
                event_code="session_revoked",
                outcome="succeeded",
                request_id=uuid4(),
                reason_code="admin_session_ended",
            )
            await session.commit()

    async def end_all_sessions(self, *, actor_id: UUID, admin_id: UUID) -> None:
        async with self._session_factory() as session:
            admin = await self._other_admin(session, actor_id, admin_id)
            admin.sessions_valid_after = self._clock()
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=actor_id,
                target_kind="admin",
                target_id=admin.id,
                event_code="session_revoked",
                outcome="succeeded",
                request_id=uuid4(),
                reason_code="admin_sessions_ended",
            )
            await session.commit()

    async def _other_admin(
        self, session: AsyncSession, actor_id: UUID, admin_id: UUID
    ) -> AdminUser:
        if admin_id == actor_id:
            raise AdminManagementRejected(
                "Change your own account on the Security page.",
                status_code=status.HTTP_403_FORBIDDEN,
            )
        admin = await session.scalar(
            select(AdminUser).where(AdminUser.id == admin_id).with_for_update()
        )
        if admin is None:
            raise AdminManagementRejected(_GENERIC_DETAIL, status_code=404)
        return admin

    async def _summary_in(self, session: AsyncSession, admin: AdminUser) -> AdminSummary:
        enrolled = await session.scalar(
            select(AdminTotpCredential.id).where(
                AdminTotpCredential.admin_user_id == admin.id,
                AdminTotpCredential.state == "active",
            )
        )
        return _summary(admin, enrolled is not None)


def _summary(admin: AdminUser, has_authenticator: bool) -> AdminSummary:
    return AdminSummary(
        admin_id=admin.id,
        email=admin.email,
        username=admin.username,
        role=admin.role,
        state=admin.state,
        has_authenticator=has_authenticator,
        created_at=admin.created_at,
        disabled_at=admin.disabled_at,
    )


# --- HTTP -----------------------------------------------------------------

router = APIRouter(prefix="/v1/admin/admins", tags=["admin-admins"])


class AdminItem(BaseModel):
    id: UUID
    email: str
    username: str | None
    role: AdminRole
    state: AdminState
    has_authenticator: bool
    created_at: datetime
    disabled_at: datetime | None
    is_you: bool


class AdminListResponse(BaseModel):
    items: list[AdminItem]


class InviteAdminRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=320, pattern=r"^[^@\s]+@[^@\s]+$")
    username: str | None = Field(default=None, min_length=1, max_length=32)
    role: AdminRole


class InvitedAdminResponse(BaseModel):
    admin: AdminItem
    temporary_password: str


class ChangeRoleRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: AdminRole


class AdminSessionItem(BaseModel):
    session_id: UUID
    mfa_method: str
    created_at: datetime
    last_seen_at: datetime
    expires_at: datetime
    is_this_one: bool


class AdminSessionListResponse(BaseModel):
    items: list[AdminSessionItem]


def _service(request: Request) -> AdminManagementService:
    service = getattr(request.app.state, "admin_management_service", None)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin management is temporarily unavailable",
        )
    return cast(AdminManagementService, service)


def _raise(error: Exception) -> NoReturn:
    if isinstance(error, AdminManagementRejected):
        raise HTTPException(status_code=error.status_code, detail=str(error)) from None
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Admin management is temporarily unavailable",
    ) from None


def _item(summary: AdminSummary, you: UUID) -> AdminItem:
    return AdminItem(
        id=summary.admin_id,
        email=summary.email,
        username=summary.username,
        role=summary.role,
        state=summary.state,
        has_authenticator=summary.has_authenticator,
        created_at=summary.created_at,
        disabled_at=summary.disabled_at,
        is_you=summary.admin_id == you,
    )


async def _owner(request: Request) -> AdminPrincipal:
    principal = await require_admin_session(request)
    if principal.role != AdminRole.OWNER:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Request denied")
    return principal


async def _owner_mutation(request: Request) -> UUID:
    principal = await authorize_admin_mutation(request, allowed_roles=_OWNER, require_step_up=True)
    return principal.admin_id


@router.get("/", response_model=AdminListResponse)
async def list_admins(request: Request) -> AdminListResponse:
    you = (await _owner(request)).admin_id
    admins = await _service(request).list_admins()
    return AdminListResponse(items=[_item(a, you) for a in admins])


@router.post("/", response_model=InvitedAdminResponse, status_code=status.HTTP_201_CREATED)
async def invite_admin(
    body: InviteAdminRequest, request: Request, response: Response
) -> InvitedAdminResponse:
    you = await _owner_mutation(request)
    try:
        invited = await _service(request).invite(
            actor_id=you, email=body.email, username=body.username, role=body.role
        )
    except AdminManagementRejected as error:
        _raise(error)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None
    apply_auth_response_headers(response)
    return InvitedAdminResponse(
        admin=_item(invited.admin, you), temporary_password=invited.temporary_password
    )


@router.post("/{admin_id}/role", response_model=AdminItem)
async def change_role(
    admin_id: UUID, body: ChangeRoleRequest, request: Request, response: Response
) -> AdminItem:
    you = await _owner_mutation(request)
    try:
        summary = await _service(request).change_role(
            actor_id=you, admin_id=admin_id, role=body.role
        )
    except AdminManagementRejected as error:
        _raise(error)
    apply_auth_response_headers(response)
    return _item(summary, you)


@router.post("/{admin_id}/disable", response_model=AdminItem)
async def disable_admin(admin_id: UUID, request: Request, response: Response) -> AdminItem:
    you = await _owner_mutation(request)
    try:
        summary = await _service(request).set_disabled(
            actor_id=you, admin_id=admin_id, disabled=True
        )
    except AdminManagementRejected as error:
        _raise(error)
    apply_auth_response_headers(response)
    return _item(summary, you)


@router.post("/{admin_id}/reactivate", response_model=AdminItem)
async def reactivate_admin(admin_id: UUID, request: Request, response: Response) -> AdminItem:
    you = await _owner_mutation(request)
    try:
        summary = await _service(request).set_disabled(
            actor_id=you, admin_id=admin_id, disabled=False
        )
    except AdminManagementRejected as error:
        _raise(error)
    apply_auth_response_headers(response)
    return _item(summary, you)


@router.get("/{admin_id}/sessions", response_model=AdminSessionListResponse)
async def list_sessions(admin_id: UUID, request: Request) -> AdminSessionListResponse:
    principal = await _owner(request)
    try:
        records = await _service(request).sessions(admin_id)
    except (AdminManagementRejected, AuthStateUnavailable) as error:
        _raise(error)
    return AdminSessionListResponse(
        items=[
            AdminSessionItem(
                session_id=r.session_id,
                mfa_method=r.mfa_method,
                created_at=r.created_at,
                last_seen_at=r.last_seen_at,
                expires_at=r.absolute_expires_at,
                is_this_one=r.session_id == principal.session_id,
            )
            for r in records
        ]
    )


@router.post("/{admin_id}/sessions/{session_id}/end", status_code=status.HTTP_204_NO_CONTENT)
async def end_session(
    admin_id: UUID, session_id: UUID, request: Request, response: Response
) -> Response:
    you = await _owner_mutation(request)
    try:
        await _service(request).end_session(actor_id=you, admin_id=admin_id, session_id=session_id)
    except (AdminManagementRejected, AuthStateUnavailable) as error:
        _raise(error)
    response.status_code = status.HTTP_204_NO_CONTENT
    apply_auth_response_headers(response)
    return response


@router.post("/{admin_id}/sessions/end-all", status_code=status.HTTP_204_NO_CONTENT)
async def end_all_sessions(admin_id: UUID, request: Request, response: Response) -> Response:
    you = await _owner_mutation(request)
    try:
        await _service(request).end_all_sessions(actor_id=you, admin_id=admin_id)
    except AdminManagementRejected as error:
        _raise(error)
    response.status_code = status.HTTP_204_NO_CONTENT
    apply_auth_response_headers(response)
    return response
