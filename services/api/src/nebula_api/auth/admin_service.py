"""Password, durable MFA, and Redis-backed administrator authentication."""

import base64
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal, cast
from urllib.parse import quote, urlencode, urlsplit
from uuid import UUID, uuid4

from sqlalchemy import or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from webauthn import (
    generate_authentication_options,
    generate_registration_options,
    options_to_json,
    verify_authentication_response,
    verify_registration_response,
)
from webauthn.helpers import base64url_to_bytes
from webauthn.helpers.exceptions import WebAuthnException
from webauthn.helpers.structs import (
    AuthenticatorSelectionCriteria,
    PublicKeyCredentialDescriptor,
    ResidentKeyRequirement,
    UserVerificationRequirement,
)

from nebula_api.auth.audit import add_audit_event
from nebula_api.auth.key_material import AuthKeyMaterial
from nebula_api.auth.mfa import (
    EncryptedMfaSeed,
    MfaEncryptionError,
    decrypt_mfa_seed,
    encrypt_mfa_seed,
    generate_mfa_seed,
    generate_recovery_codes,
    verify_totp,
)
from nebula_api.auth.opaque_tokens import OpaqueTokenError, digest_opaque_token
from nebula_api.auth.redis_state import (
    AdminSessionRecord,
    IssuedAdminSession,
    RateBucket,
    RedisAuthState,
    SessionMethod,
)
from nebula_api.auth.user_service import (
    AuthenticationRateLimited,
    AuthenticationRejected,
    sign_in_slot,
)
from nebula_api.db.engine import SessionFactory
from nebula_api.identity import normalize_email, normalize_username
from nebula_api.models.identity import (
    AdminMfaRecoveryCode,
    AdminPasskey,
    AdminTotpCredential,
    AdminUser,
)
from nebula_api.models.types import AdminRole, AdminState
from nebula_api.passwords import (
    hash_password_async,
    password_hash_needs_rehash,
    validate_password,
    verify_password_or_dummy_async,
)
from nebula_api.settings import Settings

Clock = Callable[[], datetime]
MfaMethod = Literal["totp", "recovery"]


@dataclass(frozen=True, slots=True, repr=False)
class AdminPasswordChallenge:
    token: str
    next_step: Literal["mfa", "enroll"]
    expires_in_seconds: int

    def __repr__(self) -> str:
        return "AdminPasswordChallenge(token=<redacted>)"


@dataclass(frozen=True, slots=True, repr=False)
class AdminEnrollment:
    challenge: str
    expires_in_seconds: int
    base32_secret: str
    provisioning_uri: str

    def __repr__(self) -> str:
        return "AdminEnrollment(challenge=<redacted>, secret=<redacted>)"


@dataclass(frozen=True, slots=True, repr=False)
class AdminAuthentication:
    session: IssuedAdminSession
    recovery_codes: tuple[str, ...] = ()

    def __repr__(self) -> str:
        return "AdminAuthentication(session=<redacted>, recovery_codes=<redacted>)"


@dataclass(frozen=True, slots=True)
class AdminPrincipal:
    admin_id: UUID
    session_id: UUID
    role: AdminRole
    step_up: bool
    mfa_method: SessionMethod


@dataclass(frozen=True, slots=True)
class MfaVerification:
    recovery_code_id: UUID | None = None


class AdminCredentialRejected(Exception):
    """A change to an admin's own password or authenticator refused, and why
    (safe to show to that admin)."""


@dataclass(frozen=True, slots=True, repr=False)
class AdminAuthenticatorSetup:
    base32_secret: str
    provisioning_uri: str


@dataclass(frozen=True, slots=True)
class AdminPasskeySummary:
    passkey_id: UUID
    name: str
    created_at: datetime
    last_used_at: datetime | None


# How long a passkey prompt may stay open.
_WEBAUTHN_TTL_SECONDS = 300
# Any failure to read what a browser sent is the same refusal.
_WEBAUTHN_ERRORS = (WebAuthnException, ValueError, KeyError, TypeError)


class AdminAuthService:
    """Keep privileged identity durable while treating Redis sessions as disposable."""

    def __init__(
        self,
        session_factory: SessionFactory,
        redis_state: RedisAuthState,
        key_material: AuthKeyMaterial,
        settings: Settings,
        *,
        clock: Clock = lambda: datetime.now(UTC),
    ) -> None:
        self._session_factory = session_factory
        self._redis = redis_state
        self._keys = key_material
        self._settings = settings
        self._clock = clock

    async def password_challenge(
        self,
        *,
        identifier: str,
        password: str,
        network_prefix: str,
        request_id: UUID,
    ) -> AdminPasswordChallenge:
        async with sign_in_slot():
            return await self._password_challenge(
                identifier=identifier,
                password=password,
                network_prefix=network_prefix,
                request_id=request_id,
            )

    async def _password_challenge(
        self,
        *,
        identifier: str,
        password: str,
        network_prefix: str,
        request_id: UUID,
    ) -> AdminPasswordChallenge:
        normalized = _normalize_admin_identifier(identifier)
        async with self._session_factory() as session:
            admin = await self._find_admin(session, normalized, for_update=True)
            account_key = str(admin.id) if admin is not None else normalized
            # The account's bucket is per network too: keyed on the account
            # alone, five requests from anywhere naming an admin kept that
            # admin from signing in (audit AUD-005). The second factor is
            # what stands between a guessed password and a session.
            allowed = await self._redis.rate_limit(
                (
                    RateBucket("admin-account", f"{account_key} {network_prefix}"),
                    RateBucket("admin-login-network", network_prefix),
                ),
                limit=self._settings.admin_login_rate_limit,
                window_seconds=self._settings.auth_rate_window_seconds,
            )
            if not allowed:
                add_audit_event(
                    session,
                    actor_kind="anonymous",
                    actor_id=None,
                    target_kind="auth_attempt",
                    target_id=request_id,
                    event_code="auth_rate_limited",
                    outcome="denied",
                    request_id=request_id,
                    reason_code="rate_limited",
                )
                await session.commit()
                raise AuthenticationRateLimited(self._settings.auth_rate_window_seconds)
            lockout = await self._redis.lockout_status(account_key)
            password_valid = await verify_password_or_dummy_async(
                admin.password_hash if admin is not None else None,
                password,
            )
            eligible = (
                admin is not None
                and admin.state is AdminState.ACTIVE
                and not lockout.locked
                and password_valid
            )
            if not eligible:
                # A wrong password no longer counts toward the lockout: anyone
                # could then lock an admin out by name. Only second-factor
                # failures, after the password was proven, do (AUD-005).
                add_audit_event(
                    session,
                    actor_kind="anonymous",
                    actor_id=None,
                    target_kind="auth_attempt",
                    target_id=request_id,
                    event_code="admin_authenticated",
                    outcome="denied",
                    request_id=request_id,
                    reason_code="invalid_credentials",
                )
                await session.commit()
                raise AuthenticationRejected("Authentication was not accepted")
            if admin is None:
                raise AuthenticationRejected("Authentication was not accepted")
            if password_hash_needs_rehash(admin.password_hash):
                admin.password_hash = await hash_password_async(password)
            credential = await session.scalar(
                select(AdminTotpCredential).where(
                    AdminTotpCredential.admin_user_id == admin.id,
                    AdminTotpCredential.state == "active",
                )
            )
            next_step: Literal["mfa", "enroll"] = "mfa" if credential else "enroll"
            challenge = await self._redis.issue_preauth(
                admin_id=admin.id,
                purpose="login" if next_step == "mfa" else "enroll",
                context=network_prefix,
                ttl_seconds=self._settings.admin_preauth_ttl_minutes * 60,
            )
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin",
                target_id=admin.id,
                event_code="admin_mfa_challenged",
                outcome="succeeded",
                request_id=request_id,
            )
            await session.commit()
        return AdminPasswordChallenge(
            token=challenge.token,
            next_step=next_step,
            expires_in_seconds=challenge.expires_in_seconds,
        )

    async def start_enrollment(
        self,
        *,
        challenge: str,
        network_prefix: str,
        request_id: UUID,
    ) -> AdminEnrollment:
        consumed = await self._redis.consume_preauth(
            challenge,
            purpose="enroll",
            context=network_prefix,
        )
        if consumed is None:
            raise AuthenticationRejected("Authentication was not accepted")
        now = self._now()
        credential_id = uuid4()
        seed = generate_mfa_seed()
        envelope = encrypt_mfa_seed(
            seed,
            admin_id=consumed.admin_id,
            credential_id=credential_id,
            key_version=self._settings.mfa_key_version,
            key_ring=self._keys.mfa_encryption_keys,
        )
        async with self._session_factory() as session:
            admin = await session.scalar(
                select(AdminUser).where(AdminUser.id == consumed.admin_id).with_for_update()
            )
            if admin is None or admin.state is not AdminState.ACTIVE:
                raise AuthenticationRejected("Authentication was not accepted")
            active = await session.scalar(
                select(AdminTotpCredential).where(
                    AdminTotpCredential.admin_user_id == admin.id,
                    AdminTotpCredential.state == "active",
                )
            )
            if active is not None:
                raise AuthenticationRejected("Authentication was not accepted")
            await session.execute(
                update(AdminTotpCredential)
                .where(
                    AdminTotpCredential.admin_user_id == admin.id,
                    AdminTotpCredential.state == "pending",
                )
                .values(
                    state="revoked",
                    secret_ciphertext=None,
                    secret_nonce=None,
                    key_version=None,
                    revoked_at=now,
                )
            )
            session.add(
                AdminTotpCredential(
                    id=credential_id,
                    admin_user_id=admin.id,
                    state="pending",
                    secret_ciphertext=envelope.ciphertext,
                    secret_nonce=envelope.nonce,
                    key_version=envelope.key_version,
                )
            )
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_totp_credential",
                target_id=credential_id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="enrollment_started",
            )
            await session.commit()
            email = admin.email
        confirmation = await self._redis.issue_preauth(
            admin_id=consumed.admin_id,
            purpose="enroll",
            context=network_prefix,
            ttl_seconds=self._settings.admin_preauth_ttl_minutes * 60,
        )
        encoded_seed = base64.b32encode(seed).decode("ascii").rstrip("=")
        return AdminEnrollment(
            challenge=confirmation.token,
            expires_in_seconds=confirmation.expires_in_seconds,
            base32_secret=encoded_seed,
            provisioning_uri=_provisioning_uri(encoded_seed, email),
        )

    async def confirm_enrollment(
        self,
        *,
        challenge: str,
        code: str,
        network_prefix: str,
        request_id: UUID,
    ) -> AdminAuthentication:
        consumed = await self._consume_mfa_challenge(
            challenge,
            purpose="enroll",
            network_prefix=network_prefix,
        )
        now = self._now()
        issued_session: IssuedAdminSession | None = None
        async with self._session_factory() as session:
            admin = await self._active_admin(session, consumed.admin_id, for_update=True)
            credential = await session.scalar(
                select(AdminTotpCredential)
                .where(
                    AdminTotpCredential.admin_user_id == consumed.admin_id,
                    AdminTotpCredential.state == "pending",
                )
                .with_for_update()
            )
            if admin is None or credential is None:
                raise AuthenticationRejected("Authentication was not accepted")
            accepted_step = self._verify_totp_credential(credential, admin.id, code)
            if accepted_step is None:
                await self._record_mfa_denial(
                    session,
                    admin_id=admin.id,
                    request_id=request_id,
                    reason_code="invalid_mfa",
                )
                raise AuthenticationRejected("Authentication was not accepted")
            credential.state = "active"
            credential.confirmed_at = now
            credential.last_accepted_timestep = accepted_step
            batch = generate_recovery_codes(
                self._keys.token_peppers,
                key_version=self._settings.token_key_version,
            )
            session.add_all(
                AdminMfaRecoveryCode(
                    id=uuid4(),
                    admin_totp_credential_id=credential.id,
                    code_digest=item.value,
                    key_version=item.key_version,
                    state="active",
                )
                for item in batch.digests
            )
            issued_session = await self._new_admin_session(admin.id, "totp")
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_totp_credential",
                target_id=credential.id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="enrollment_confirmed",
            )
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_session",
                target_id=issued_session.record.session_id,
                event_code="admin_authenticated",
                outcome="succeeded",
                request_id=request_id,
            )
            try:
                await session.commit()
            except BaseException:
                await self._redis.revoke_admin_session(issued_session.session_token)
                raise
        await self._redis.clear_admin_failures(str(consumed.admin_id))
        return AdminAuthentication(
            session=issued_session,
            recovery_codes=batch.take_plaintext_codes(),
        )

    async def verify_mfa(
        self,
        *,
        challenge: str,
        code: str,
        method: MfaMethod,
        network_prefix: str,
        request_id: UUID,
    ) -> AdminAuthentication:
        consumed = await self._consume_mfa_challenge(
            challenge,
            purpose="login",
            network_prefix=network_prefix,
        )
        issued_session: IssuedAdminSession | None = None
        async with self._session_factory() as session:
            admin = await self._active_admin(session, consumed.admin_id, for_update=True)
            credential = await self._active_credential(session, consumed.admin_id, for_update=True)
            if admin is None or credential is None:
                raise AuthenticationRejected("Authentication was not accepted")
            verification = await self._verify_mfa_method(
                session,
                credential=credential,
                admin_id=admin.id,
                code=code,
                method=method,
            )
            if verification is None:
                await self._record_mfa_denial(
                    session,
                    admin_id=admin.id,
                    request_id=request_id,
                    reason_code="invalid_mfa",
                )
                raise AuthenticationRejected("Authentication was not accepted")
            issued_session = await self._new_admin_session(admin.id, method)
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_session",
                target_id=issued_session.record.session_id,
                event_code="admin_authenticated",
                outcome="succeeded",
                request_id=request_id,
            )
            if verification.recovery_code_id is not None:
                add_audit_event(
                    session,
                    actor_kind="admin",
                    actor_id=admin.id,
                    target_kind="admin_recovery_code",
                    target_id=verification.recovery_code_id,
                    event_code="admin_recovery_code_used",
                    outcome="succeeded",
                    request_id=request_id,
                )
            try:
                await session.commit()
            except BaseException:
                await self._redis.revoke_admin_session(issued_session.session_token)
                raise
        await self._redis.clear_admin_failures(str(consumed.admin_id))
        return AdminAuthentication(session=issued_session)

    async def principal(self, session_token: str) -> AdminPrincipal:
        record = await self._redis.get_admin_session(
            session_token,
            idle_ttl=timedelta(minutes=self._settings.admin_session_ttl_minutes),
        )
        if record is None:
            raise AuthenticationRejected("Authentication was not accepted")
        async with self._session_factory() as session:
            admin = await self._active_admin(session, record.admin_id, for_update=False)
        if admin is None or (
            admin.sessions_valid_after is not None
            and record.created_at < admin.sessions_valid_after
        ):
            await self._redis.revoke_admin_session(session_token)
            raise AuthenticationRejected("Authentication was not accepted")
        return AdminPrincipal(
            admin_id=admin.id,
            session_id=record.session_id,
            role=admin.role,
            step_up=_is_step_up_fresh(
                record,
                self._now(),
                timedelta(minutes=self._settings.admin_step_up_ttl_minutes),
            ),
            mfa_method=record.mfa_method,
        )

    async def validate_and_rotate_csrf(self, session_token: str, csrf_token: str) -> str:
        replacement = await self._redis.validate_and_rotate_csrf(
            session_token,
            csrf_token,
            idle_ttl=timedelta(minutes=self._settings.admin_session_ttl_minutes),
        )
        if replacement is None:
            raise AuthenticationRejected("Request denied")
        return replacement

    async def step_up(
        self,
        *,
        session_token: str,
        code: str,
        method: MfaMethod,
        network_prefix: str,
        request_id: UUID,
    ) -> AdminAuthentication:
        principal = await self.principal(session_token)
        account_key = str(principal.admin_id)
        if not await self._redis.rate_limit(
            (
                RateBucket("admin-step-up-account", account_key),
                RateBucket("admin-step-up-network", network_prefix),
            ),
            limit=self._settings.admin_mfa_rate_limit,
            window_seconds=self._settings.auth_rate_window_seconds,
        ):
            raise AuthenticationRateLimited(self._settings.auth_rate_window_seconds)
        if (await self._redis.lockout_status(account_key)).locked:
            raise AuthenticationRejected("Authentication was not accepted")
        async with self._session_factory() as session:
            admin = await self._active_admin(session, principal.admin_id, for_update=True)
            credential = await self._active_credential(session, principal.admin_id, for_update=True)
            if admin is None or credential is None:
                raise AuthenticationRejected("Authentication was not accepted")
            verification = await self._verify_mfa_method(
                session,
                credential=credential,
                admin_id=admin.id,
                code=code,
                method=method,
            )
            if verification is None:
                await self._record_mfa_denial(
                    session,
                    admin_id=admin.id,
                    request_id=request_id,
                    reason_code="invalid_step_up",
                )
                raise AuthenticationRejected("Authentication was not accepted")
            replacement = await self._redis.rotate_admin_session(
                session_token,
                idle_ttl=timedelta(minutes=self._settings.admin_session_ttl_minutes),
                stepped_up=True,
            )
            if replacement is None:
                raise AuthenticationRejected("Authentication was not accepted")
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_session",
                target_id=replacement.record.session_id,
                event_code="admin_mfa_challenged",
                outcome="succeeded",
                request_id=request_id,
                reason_code="step_up",
            )
            if verification.recovery_code_id is not None:
                add_audit_event(
                    session,
                    actor_kind="admin",
                    actor_id=admin.id,
                    target_kind="admin_recovery_code",
                    target_id=verification.recovery_code_id,
                    event_code="admin_recovery_code_used",
                    outcome="succeeded",
                    request_id=request_id,
                )
            try:
                await session.commit()
            except BaseException:
                await self._redis.revoke_admin_session(replacement.session_token)
                raise
        await self._redis.clear_admin_failures(account_key)
        return AdminAuthentication(session=replacement)

    async def logout(self, session_token: str, *, request_id: UUID) -> None:
        try:
            principal = await self.principal(session_token)
        except AuthenticationRejected:
            await self._redis.revoke_admin_session(session_token)
            return
        await self._redis.revoke_admin_session(session_token)
        async with self._session_factory() as session:
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=principal.admin_id,
                target_kind="admin_session",
                target_id=principal.session_id,
                event_code="session_revoked",
                outcome="succeeded",
                request_id=request_id,
            )
            await session.commit()

    async def rotate_recovery_codes(
        self,
        *,
        session_token: str,
        request_id: UUID,
    ) -> tuple[str, ...]:
        principal = await self.principal(session_token)
        if not principal.step_up:
            raise AuthenticationRejected("Authentication was not accepted")
        now = self._now()
        async with self._session_factory() as session:
            credential = await self._active_credential(session, principal.admin_id, for_update=True)
            if credential is None:
                raise AuthenticationRejected("Authentication was not accepted")
            await session.execute(
                update(AdminMfaRecoveryCode)
                .where(
                    AdminMfaRecoveryCode.admin_totp_credential_id == credential.id,
                    AdminMfaRecoveryCode.state == "active",
                )
                .values(state="revoked", revoked_at=now)
            )
            batch = generate_recovery_codes(
                self._keys.token_peppers,
                key_version=self._settings.token_key_version,
            )
            session.add_all(
                AdminMfaRecoveryCode(
                    id=uuid4(),
                    admin_totp_credential_id=credential.id,
                    code_digest=item.value,
                    key_version=item.key_version,
                    state="active",
                )
                for item in batch.digests
            )
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=principal.admin_id,
                target_kind="admin_totp_credential",
                target_id=credential.id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="recovery_codes_rotated",
            )
            await session.commit()
        return batch.take_plaintext_codes()

    async def change_password(
        self,
        *,
        session_token: str,
        current_password: str,
        new_password: str,
        request_id: UUID,
    ) -> IssuedAdminSession:
        """Change the signed-in admin's password; every session of theirs ends.

        Needs a fresh step-up and the current password. The caller gets a new
        session in place of the one it used, so it stays signed in here.
        """

        principal = await self._stepped_up(session_token)
        try:
            validate_password(new_password)
        except ValueError as error:
            message = str(error)
            raise AdminCredentialRejected(message[:1].upper() + message[1:] + ".") from None
        await self._limit_own_change("admin-password-change", principal.admin_id)
        now = self._now()
        async with self._session_factory() as session:
            admin = await self._active_admin(session, principal.admin_id, for_update=True)
            if admin is None:
                raise AuthenticationRejected("Authentication was not accepted")
            if not await verify_password_or_dummy_async(admin.password_hash, current_password):
                add_audit_event(
                    session,
                    actor_kind="admin",
                    actor_id=admin.id,
                    target_kind="admin",
                    target_id=admin.id,
                    event_code="password_changed",
                    outcome="denied",
                    request_id=request_id,
                    reason_code="invalid_password",
                )
                await session.commit()
                raise AdminCredentialRejected("The current password is not right.")
            admin.password_hash = await hash_password_async(new_password)
            admin.sessions_valid_after = now
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin",
                target_id=admin.id,
                event_code="password_changed",
                outcome="succeeded",
                request_id=request_id,
            )
            await session.commit()
        await self._redis.revoke_admin_session(session_token)
        return await self._redis.issue_admin_session(
            admin_id=principal.admin_id,
            mfa_method=principal.mfa_method,
            idle_ttl=timedelta(minutes=self._settings.admin_session_ttl_minutes),
            absolute_ttl=timedelta(hours=self._settings.admin_session_absolute_ttl_hours),
            stepped_up=True,
        )

    async def start_authenticator_replacement(
        self, *, session_token: str, request_id: UUID
    ) -> AdminAuthenticatorSetup:
        """A new authenticator to set up. The current one keeps working until
        the new one is confirmed, so a failed setup cannot lock anyone out."""

        principal = await self._stepped_up(session_token)
        now = self._now()
        credential_id = uuid4()
        seed = generate_mfa_seed()
        envelope = encrypt_mfa_seed(
            seed,
            admin_id=principal.admin_id,
            credential_id=credential_id,
            key_version=self._settings.mfa_key_version,
            key_ring=self._keys.mfa_encryption_keys,
        )
        async with self._session_factory() as session:
            admin = await self._active_admin(session, principal.admin_id, for_update=True)
            if admin is None:
                raise AuthenticationRejected("Authentication was not accepted")
            await session.execute(
                update(AdminTotpCredential)
                .where(
                    AdminTotpCredential.admin_user_id == admin.id,
                    AdminTotpCredential.state == "pending",
                )
                .values(
                    state="revoked",
                    secret_ciphertext=None,
                    secret_nonce=None,
                    key_version=None,
                    revoked_at=now,
                )
            )
            session.add(
                AdminTotpCredential(
                    id=credential_id,
                    admin_user_id=admin.id,
                    state="pending",
                    secret_ciphertext=envelope.ciphertext,
                    secret_nonce=envelope.nonce,
                    key_version=envelope.key_version,
                )
            )
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_totp_credential",
                target_id=credential_id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="replacement_started",
            )
            await session.commit()
            email = admin.email
        encoded_seed = base64.b32encode(seed).decode("ascii").rstrip("=")
        return AdminAuthenticatorSetup(
            base32_secret=encoded_seed,
            provisioning_uri=_provisioning_uri(encoded_seed, email),
        )

    async def confirm_authenticator_replacement(
        self, *, session_token: str, code: str, request_id: UUID
    ) -> tuple[str, ...]:
        """Switch to the new authenticator once it gives a right code.

        The old one and its recovery codes stop working; new recovery codes
        are returned, once.
        """

        principal = await self._stepped_up(session_token)
        await self._limit_own_change("admin-mfa-replace", principal.admin_id)
        now = self._now()
        async with self._session_factory() as session:
            pending = await session.scalar(
                select(AdminTotpCredential)
                .where(
                    AdminTotpCredential.admin_user_id == principal.admin_id,
                    AdminTotpCredential.state == "pending",
                )
                .with_for_update()
            )
            if pending is None:
                raise AdminCredentialRejected("Start the new authenticator setup again.")
            accepted_step = self._verify_totp_credential(pending, principal.admin_id, code)
            if accepted_step is None:
                raise AdminCredentialRejected(
                    "That code is not from the new authenticator, or it has expired."
                )
            old = await self._active_credential(session, principal.admin_id, for_update=True)
            if old is not None:
                await session.execute(
                    update(AdminMfaRecoveryCode)
                    .where(
                        AdminMfaRecoveryCode.admin_totp_credential_id == old.id,
                        AdminMfaRecoveryCode.state == "active",
                    )
                    .values(state="revoked", revoked_at=now)
                )
                old.state = "revoked"
                old.secret_ciphertext = None
                old.secret_nonce = None
                old.key_version = None
                old.revoked_at = now
                # One active credential per admin is a unique index.
                await session.flush()
            pending.state = "active"
            pending.confirmed_at = now
            pending.last_accepted_timestep = accepted_step
            batch = generate_recovery_codes(
                self._keys.token_peppers,
                key_version=self._settings.token_key_version,
            )
            session.add_all(
                AdminMfaRecoveryCode(
                    id=uuid4(),
                    admin_totp_credential_id=pending.id,
                    code_digest=item.value,
                    key_version=item.key_version,
                    state="active",
                )
                for item in batch.digests
            )
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=principal.admin_id,
                target_kind="admin_totp_credential",
                target_id=pending.id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="replacement_confirmed",
            )
            await session.commit()
        return batch.take_plaintext_codes()

    # --- Passkeys ---------------------------------------------------------
    #
    # Sign-in only: after the password, a passkey stands in for the code.
    # Step-up keeps asking for the code.

    def _origins(self) -> list[str]:
        return [origin.strip() for origin in self._settings.allowed_origins.split(",")]

    def _rp_id(self) -> str:
        # ponytail: the first allowed origin names the panel; a second panel
        # host would need its own relying party.
        return urlsplit(self._origins()[0]).hostname or "localhost"

    async def list_passkeys(self, admin_id: UUID) -> list[AdminPasskeySummary]:
        async with self._session_factory() as session:
            rows = (
                await session.scalars(
                    select(AdminPasskey)
                    .where(AdminPasskey.admin_user_id == admin_id)
                    .order_by(AdminPasskey.created_at)
                )
            ).all()
        return [_passkey_summary(row) for row in rows]

    async def passkey_registration_options(self, *, session_token: str) -> str:
        principal = await self._stepped_up(session_token)
        async with self._session_factory() as session:
            admin = await self._active_admin(session, principal.admin_id, for_update=False)
            if admin is None:
                raise AuthenticationRejected("Authentication was not accepted")
            existing = (
                await session.scalars(
                    select(AdminPasskey.credential_id).where(AdminPasskey.admin_user_id == admin.id)
                )
            ).all()
        options = generate_registration_options(
            rp_id=self._rp_id(),
            rp_name="Nebula VPN admin panel",
            user_name=admin.email,
            user_id=admin.id.bytes,
            authenticator_selection=AuthenticatorSelectionCriteria(
                resident_key=ResidentKeyRequirement.PREFERRED,
                user_verification=UserVerificationRequirement.PREFERRED,
            ),
            exclude_credentials=[PublicKeyCredentialDescriptor(id=c) for c in existing],
        )
        await self._redis.put_webauthn_challenge(
            f"register:{principal.session_id}",
            admin_id=principal.admin_id,
            challenge=options.challenge,
            ttl_seconds=_WEBAUTHN_TTL_SECONDS,
        )
        return options_to_json(options)

    async def register_passkey(
        self,
        *,
        session_token: str,
        name: str,
        credential: dict[str, object],
        request_id: UUID,
    ) -> AdminPasskeySummary:
        principal = await self._stepped_up(session_token)
        challenge = await self._redis.take_webauthn_challenge(
            f"register:{principal.session_id}", admin_id=principal.admin_id
        )
        if challenge is None:
            raise AdminCredentialRejected("The passkey request ran out of time. Start again.")
        try:
            verified = verify_registration_response(
                credential=credential,
                expected_challenge=challenge,
                expected_rp_id=self._rp_id(),
                expected_origin=self._origins(),
            )
        except _WEBAUTHN_ERRORS:
            raise AdminCredentialRejected("This passkey could not be checked. Try again.") from None
        async with self._session_factory() as session:
            taken = await session.scalar(
                select(AdminPasskey.id).where(AdminPasskey.credential_id == verified.credential_id)
            )
            if taken is not None:
                raise AdminCredentialRejected("This passkey is already added.")
            row = AdminPasskey(
                admin_user_id=principal.admin_id,
                credential_id=verified.credential_id,
                public_key=verified.credential_public_key,
                sign_count=verified.sign_count,
                name=name.strip(),
                # Set here: the database default is not loaded after an insert.
                created_at=self._now(),
            )
            session.add(row)
            await session.flush()
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=principal.admin_id,
                target_kind="admin",
                target_id=principal.admin_id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="passkey_added",
            )
            await session.commit()
            return _passkey_summary(row)

    async def remove_passkey(
        self, *, session_token: str, passkey_id: UUID, request_id: UUID
    ) -> None:
        principal = await self._stepped_up(session_token)
        async with self._session_factory() as session:
            row = await session.scalar(
                select(AdminPasskey)
                .where(
                    AdminPasskey.id == passkey_id,
                    AdminPasskey.admin_user_id == principal.admin_id,
                )
                .with_for_update()
            )
            if row is None:
                raise AdminCredentialRejected("That passkey is already removed.")
            await session.delete(row)
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=principal.admin_id,
                target_kind="admin",
                target_id=principal.admin_id,
                event_code="admin_mfa_changed",
                outcome="succeeded",
                request_id=request_id,
                reason_code="passkey_removed",
            )
            await session.commit()

    async def passkey_login_options(self, *, challenge: str, network_prefix: str) -> str:
        """A passkey prompt for the admin a sign-in challenge belongs to.

        The challenge is only read, so cancelling the prompt leaves the code.
        """

        admin_id = await self._redis.peek_preauth(
            challenge, purpose="login", context=network_prefix
        )
        if admin_id is None:
            raise AuthenticationRejected("Authentication was not accepted")
        async with self._session_factory() as session:
            credentials = (
                await session.scalars(
                    select(AdminPasskey.credential_id).where(AdminPasskey.admin_user_id == admin_id)
                )
            ).all()
        if not credentials:
            raise AdminCredentialRejected("No passkey is set up for this account. Use the code.")
        options = generate_authentication_options(
            rp_id=self._rp_id(),
            allow_credentials=[PublicKeyCredentialDescriptor(id=c) for c in credentials],
            user_verification=UserVerificationRequirement.PREFERRED,
        )
        await self._redis.put_webauthn_challenge(
            f"login:{challenge}",
            admin_id=admin_id,
            challenge=options.challenge,
            ttl_seconds=_WEBAUTHN_TTL_SECONDS,
        )
        return options_to_json(options)

    async def verify_passkey_login(
        self,
        *,
        challenge: str,
        credential: dict[str, object],
        network_prefix: str,
        request_id: UUID,
    ) -> AdminAuthentication:
        consumed = await self._consume_mfa_challenge(
            challenge, purpose="login", network_prefix=network_prefix
        )
        expected = await self._redis.take_webauthn_challenge(
            f"login:{challenge}", admin_id=consumed.admin_id
        )
        issued_session: IssuedAdminSession | None = None
        async with self._session_factory() as session:
            admin = await self._active_admin(session, consumed.admin_id, for_update=True)
            if admin is None or expected is None:
                raise AuthenticationRejected("Authentication was not accepted")
            try:
                raw_id = base64url_to_bytes(str(credential["rawId"]))
            except _WEBAUTHN_ERRORS:
                raw_id = b""
            passkey = await session.scalar(
                select(AdminPasskey)
                .where(
                    AdminPasskey.admin_user_id == admin.id,
                    AdminPasskey.credential_id == raw_id,
                )
                .with_for_update()
            )
            verified = None
            if passkey is not None:
                try:
                    verified = verify_authentication_response(
                        credential=credential,
                        expected_challenge=expected,
                        expected_rp_id=self._rp_id(),
                        expected_origin=self._origins(),
                        credential_public_key=passkey.public_key,
                        credential_current_sign_count=passkey.sign_count,
                    )
                except _WEBAUTHN_ERRORS:
                    verified = None
            if passkey is None or verified is None:
                await self._record_mfa_denial(
                    session, admin_id=admin.id, request_id=request_id, reason_code="invalid_passkey"
                )
                raise AuthenticationRejected("Authentication was not accepted")
            passkey.sign_count = verified.new_sign_count
            passkey.last_used_at = self._now()
            issued_session = await self._new_admin_session(admin.id, "passkey")
            add_audit_event(
                session,
                actor_kind="admin",
                actor_id=admin.id,
                target_kind="admin_session",
                target_id=issued_session.record.session_id,
                event_code="admin_authenticated",
                outcome="succeeded",
                request_id=request_id,
                reason_code="passkey",
            )
            try:
                await session.commit()
            except BaseException:
                await self._redis.revoke_admin_session(issued_session.session_token)
                raise
        await self._redis.clear_admin_failures(str(consumed.admin_id))
        return AdminAuthentication(session=issued_session)

    async def _stepped_up(self, session_token: str) -> AdminPrincipal:
        principal = await self.principal(session_token)
        if not principal.step_up:
            raise AuthenticationRejected("Authentication was not accepted")
        return principal

    async def _limit_own_change(self, bucket: str, admin_id: UUID) -> None:
        if not await self._redis.rate_limit(
            (RateBucket(bucket, str(admin_id)),),
            limit=self._settings.admin_mfa_rate_limit,
            window_seconds=self._settings.auth_rate_window_seconds,
        ):
            raise AuthenticationRateLimited(self._settings.auth_rate_window_seconds)

    async def _consume_mfa_challenge(
        self,
        challenge: str,
        *,
        purpose: Literal["login", "enroll"],
        network_prefix: str,
    ) -> "ConsumedPreAuth":
        if not await self._redis.rate_limit(
            (
                RateBucket("mfa-challenge", challenge),
                RateBucket("admin-mfa-network", network_prefix),
            ),
            limit=self._settings.admin_mfa_rate_limit,
            window_seconds=self._settings.auth_rate_window_seconds,
        ):
            raise AuthenticationRateLimited(self._settings.auth_rate_window_seconds)
        consumed = await self._redis.consume_preauth(
            challenge,
            purpose=purpose,
            context=network_prefix,
        )
        if consumed is None:
            raise AuthenticationRejected("Authentication was not accepted")
        return consumed

    async def _verify_mfa_method(
        self,
        session: AsyncSession,
        *,
        credential: AdminTotpCredential,
        admin_id: UUID,
        code: str,
        method: MfaMethod,
    ) -> MfaVerification | None:
        if method == "totp":
            accepted_step = self._verify_totp_credential(credential, admin_id, code)
            if accepted_step is None:
                return None
            credential.last_accepted_timestep = accepted_step
            return MfaVerification()
        try:
            digest = digest_opaque_token(
                code,
                self._keys.token_peppers,
                namespace="mfa-recovery",
            )
        except (OpaqueTokenError, ValueError):
            return None
        recovery = await session.scalar(
            select(AdminMfaRecoveryCode)
            .where(
                AdminMfaRecoveryCode.admin_totp_credential_id == credential.id,
                AdminMfaRecoveryCode.key_version == digest.key_version,
                AdminMfaRecoveryCode.code_digest == digest.value,
                AdminMfaRecoveryCode.state == "active",
            )
            .with_for_update()
        )
        if recovery is None:
            return None
        recovery.state = "consumed"
        recovery.consumed_at = self._now()
        return MfaVerification(recovery_code_id=recovery.id)

    def _verify_totp_credential(
        self,
        credential: AdminTotpCredential,
        admin_id: UUID,
        code: str,
    ) -> int | None:
        if (
            credential.secret_ciphertext is None
            or credential.secret_nonce is None
            or credential.key_version is None
        ):
            return None
        try:
            seed = decrypt_mfa_seed(
                EncryptedMfaSeed(
                    key_version=credential.key_version,
                    nonce=credential.secret_nonce,
                    ciphertext=credential.secret_ciphertext,
                ),
                admin_id=admin_id,
                credential_id=credential.id,
                key_ring=self._keys.mfa_encryption_keys,
            )
        except (MfaEncryptionError, ValueError):
            return None
        accepted_step = verify_totp(
            seed,
            code,
            clock=self._clock,
            skew=self._settings.totp_allowed_skew_steps,
        )
        if accepted_step is None or (
            credential.last_accepted_timestep is not None
            and accepted_step <= credential.last_accepted_timestep
        ):
            return None
        return accepted_step

    async def _record_mfa_denial(
        self,
        session: AsyncSession,
        *,
        admin_id: UUID,
        request_id: UUID,
        reason_code: str,
    ) -> None:
        failure = await self._redis.record_admin_failure(
            str(admin_id),
            threshold=self._settings.admin_lockout_threshold,
            lock_seconds=self._settings.admin_lockout_seconds,
        )
        add_audit_event(
            session,
            actor_kind="admin",
            actor_id=admin_id,
            target_kind="admin",
            target_id=admin_id,
            event_code=("auth_lockout_changed" if failure.locked else "admin_authenticated"),
            outcome="denied",
            request_id=request_id,
            reason_code=reason_code,
        )
        await session.commit()

    async def _new_admin_session(self, admin_id: UUID, method: SessionMethod) -> IssuedAdminSession:
        return await self._redis.issue_admin_session(
            admin_id=admin_id,
            mfa_method=method,
            idle_ttl=timedelta(minutes=self._settings.admin_session_ttl_minutes),
            absolute_ttl=timedelta(hours=self._settings.admin_session_absolute_ttl_hours),
        )

    async def _find_admin(
        self,
        session: AsyncSession,
        normalized: str,
        *,
        for_update: bool,
    ) -> AdminUser | None:
        statement = select(AdminUser).where(
            or_(
                AdminUser.email_normalized == normalized,
                AdminUser.username_normalized == normalized,
            )
        )
        if for_update:
            statement = statement.with_for_update()
        return cast(AdminUser | None, await session.scalar(statement))

    async def _active_admin(
        self, session: AsyncSession, admin_id: UUID, *, for_update: bool
    ) -> AdminUser | None:
        statement = select(AdminUser).where(
            AdminUser.id == admin_id,
            AdminUser.state == AdminState.ACTIVE,
        )
        if for_update:
            statement = statement.with_for_update()
        return cast(AdminUser | None, await session.scalar(statement))

    async def _active_credential(
        self, session: AsyncSession, admin_id: UUID, *, for_update: bool
    ) -> AdminTotpCredential | None:
        statement = select(AdminTotpCredential).where(
            AdminTotpCredential.admin_user_id == admin_id,
            AdminTotpCredential.state == "active",
        )
        if for_update:
            statement = statement.with_for_update()
        return cast(AdminTotpCredential | None, await session.scalar(statement))

    def _now(self) -> datetime:
        value = self._clock()
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("authentication clock must be timezone aware")
        return value.astimezone(UTC)


def _normalize_admin_identifier(identifier: str) -> str:
    try:
        return normalize_email(identifier) if "@" in identifier else normalize_username(identifier)
    except ValueError:
        return "invalid"


def _is_step_up_fresh(record: AdminSessionRecord, now: datetime, lifetime: timedelta) -> bool:
    return record.step_up_at is not None and record.step_up_at + lifetime > now


# Avoid a runtime import cycle while retaining the precise return type above.
from nebula_api.auth.redis_state import ConsumedPreAuth  # noqa: E402


def _provisioning_uri(encoded_seed: str, email: str) -> str:
    label = quote(f"Nebula:{email}", safe="")
    query = urlencode(
        {
            "secret": encoded_seed,
            "issuer": "Nebula",
            "algorithm": "SHA1",
            "digits": "6",
            "period": "30",
        }
    )
    return f"otpauth://totp/{label}?{query}"


def _passkey_summary(row: AdminPasskey) -> AdminPasskeySummary:
    return AdminPasskeySummary(
        passkey_id=row.id,
        name=row.name,
        created_at=row.created_at,
        last_used_at=row.last_used_at,
    )
