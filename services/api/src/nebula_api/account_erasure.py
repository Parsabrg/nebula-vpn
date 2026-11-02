"""Deleting an account, strictly: shared by the person's own request and an admin's."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from nebula_api.auth.audit import add_audit_event
from nebula_api.models.approval import (
    AccountRequest,
    AccountRequestEvent,
    PasswordResetToken,
    UserActivation,
)
from nebula_api.models.identity import Device, RefreshToken, User, UserSession
from nebula_api.models.operations import EmailDelivery
from nebula_api.models.topology import UserProtocolPermission, UserServerAssignment
from nebula_api.models.types import AccountState, LifecycleState
from nebula_api.provisioning.revocation import revoke_device_credentials


async def erase_account(
    session: AsyncSession,
    user: User,
    *,
    now: datetime,
    actor_kind: str,
    actor_id: UUID,
    request_id: UUID,
) -> None:
    """Leave nothing that names the person; the caller commits.

    Removed: email, username and password; device names and hardware
    hashes; every session, token, activation and reset link; the account
    request and its history; every email queued for or sent to the
    address; permissions and server assignments. Every VPN credential goes
    to REVOKING, which reconciliation removes from each server.

    Kept, under the account's random id and nothing else: audit rows and
    traffic totals. The deletion's own audit row names no address.
    Backups still hold the old data until they age out (30 days).
    """

    address = user.email_normalized
    devices = (await session.scalars(select(Device).where(Device.user_id == user.id))).all()
    for device in devices:
        if device.state != LifecycleState.REVOKED:
            device.state = LifecycleState.REVOKED
            device.revoked_at = now
        await revoke_device_credentials(session, device.id, now)
        # Kept as rows: traffic totals hang off their credentials.
        device.name = "deleted"
        device.hardware_hash = None
        device.hardware_key_version = None
        device.updated_at = now

    session_ids = select(UserSession.id).where(UserSession.user_id == user.id)
    await session.execute(delete(RefreshToken).where(RefreshToken.session_id.in_(session_ids)))
    await session.execute(delete(UserSession).where(UserSession.user_id == user.id))
    await session.execute(delete(UserActivation).where(UserActivation.user_id == user.id))
    await session.execute(delete(PasswordResetToken).where(PasswordResetToken.user_id == user.id))
    requests = select(AccountRequest.id).where(
        or_(AccountRequest.user_id == user.id, AccountRequest.email_normalized == address)
    )
    await session.execute(
        delete(AccountRequestEvent).where(AccountRequestEvent.request_id.in_(requests))
    )
    await session.execute(
        delete(AccountRequest).where(
            or_(AccountRequest.user_id == user.id, AccountRequest.email_normalized == address)
        )
    )
    await session.execute(
        delete(EmailDelivery).where(
            or_(
                func.lower(EmailDelivery.recipient_address) == address,
                and_(EmailDelivery.subject_kind == "user", EmailDelivery.subject_id == user.id),
            )
        )
    )
    await session.execute(
        delete(UserProtocolPermission).where(UserProtocolPermission.user_id == user.id)
    )
    await session.execute(
        delete(UserServerAssignment).where(UserServerAssignment.user_id == user.id)
    )

    # Random, so it says nothing about the address it replaces.
    placeholder = f"deleted-{uuid4().hex}@deleted.invalid"
    user.email = placeholder
    user.email_normalized = placeholder
    user.username = None
    user.username_normalized = None
    user.password_hash = None
    user.state = AccountState.DISABLED
    user.disabled_at = now
    add_audit_event(
        session,
        actor_kind=actor_kind,
        actor_id=actor_id,
        target_kind="user",
        target_id=user.id,
        event_code="identity_state_changed",
        outcome="succeeded",
        request_id=request_id,
        reason_code="account_deleted",
    )
