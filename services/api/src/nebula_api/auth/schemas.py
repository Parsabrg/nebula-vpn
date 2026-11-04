"""Strict, bounded HTTP contracts for authentication endpoints."""

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator

from nebula_api.models.types import AdminRole, DevicePlatform
from nebula_api.passwords import MAXIMUM_PASSWORD_UTF8_BYTES


def _bounded_password(value: SecretStr) -> SecretStr:
    if len(value.get_secret_value().encode("utf-8")) > MAXIMUM_PASSWORD_UTF8_BYTES:
        raise ValueError("password is too large")
    return value


class AuthModel(BaseModel):
    """Reject undeclared fields so identifiers cannot be smuggled into auth flows."""

    model_config = ConfigDict(extra="forbid")


class UserLoginRequest(AuthModel):
    identifier: str = Field(min_length=3, max_length=320)
    password: SecretStr = Field(min_length=1, max_length=1024)
    device_id: UUID | None = None
    device_name: str = Field(min_length=1, max_length=80)
    platform: DevicePlatform
    client_version: str = Field(min_length=1, max_length=32, pattern=r"^[A-Za-z0-9_.+-]+$")
    # The platform's install/hardware id, so a reinstall reuses this device
    # rather than counting as a new one. Opaque and length-bounded; absent
    # from a client too old to send it.
    hardware_id: str | None = Field(default=None, min_length=1, max_length=512, pattern=r"^[!-~]+$")

    _password_size = field_validator("password")(_bounded_password)


class RefreshRequest(AuthModel):
    refresh_token: SecretStr = Field(min_length=10, max_length=128)


class LogoutRequest(RefreshRequest):
    pass


class PasswordResetRequest(AuthModel):
    identifier: str = Field(min_length=3, max_length=320)


class PasswordChangeRequest(AuthModel):
    current_password: SecretStr = Field(min_length=1, max_length=1024)
    new_password: SecretStr = Field(min_length=12, max_length=1024)

    _password_size = field_validator("current_password", "new_password")(_bounded_password)


class AccountDeletionRequest(AuthModel):
    password: SecretStr = Field(min_length=1, max_length=1024)

    _password_size = field_validator("password")(_bounded_password)


class PasswordResetConfirmRequest(AuthModel):
    token: SecretStr = Field(min_length=10, max_length=128)
    new_password: SecretStr = Field(min_length=12, max_length=1024)

    _password_size = field_validator("new_password")(_bounded_password)


class TokenPairResponse(AuthModel):
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"  # noqa: S105 - public OAuth token type
    expires_in: int


class UserPrincipalResponse(AuthModel):
    user_id: UUID
    session_id: UUID
    device_id: UUID


class NeutralAcceptedResponse(AuthModel):
    status: Literal["accepted"] = "accepted"


class AdminPasswordRequest(AuthModel):
    identifier: str = Field(min_length=3, max_length=320)
    password: SecretStr = Field(min_length=1, max_length=1024)

    _password_size = field_validator("password")(_bounded_password)


class AdminChallengeResponse(AuthModel):
    challenge: str
    next_step: Literal["mfa", "enroll"]
    expires_in: int


class AdminMfaRequest(AuthModel):
    challenge: SecretStr = Field(min_length=10, max_length=128)
    code: SecretStr = Field(min_length=6, max_length=128)
    method: Literal["totp", "recovery"] = "totp"


class AdminEnrollmentRequest(AuthModel):
    challenge: SecretStr = Field(min_length=10, max_length=128)


class AdminEnrollmentConfirmRequest(AdminEnrollmentRequest):
    code: SecretStr = Field(min_length=6, max_length=6)


class AdminEnrollmentResponse(AuthModel):
    challenge: str
    expires_in: int
    secret: str
    provisioning_uri: str
    qr_svg: str


class AdminSessionResponse(AuthModel):
    admin_id: UUID
    role: AdminRole
    csrf_token: str | None = None
    step_up: bool


class AdminRecoveryCodesResponse(AuthModel):
    recovery_codes: list[str]


class AdminEnrollmentCompleteResponse(AdminSessionResponse):
    recovery_codes: list[str]


class AdminStepUpRequest(AuthModel):
    code: SecretStr = Field(min_length=6, max_length=128)
    method: Literal["totp", "recovery"] = "totp"


class AdminPasswordChangeRequest(AuthModel):
    current_password: SecretStr = Field(min_length=1, max_length=1024)
    new_password: SecretStr = Field(min_length=1, max_length=1024)


class AdminAuthenticatorSetupResponse(AuthModel):
    secret: str
    provisioning_uri: str
    qr_svg: str


class AdminAuthenticatorConfirmRequest(AuthModel):
    code: SecretStr = Field(min_length=6, max_length=6)


class AdminPasskeyItem(AuthModel):
    id: UUID
    name: str
    created_at: datetime
    last_used_at: datetime | None


class AdminPasskeyListResponse(AuthModel):
    items: list[AdminPasskeyItem]


class AdminPasskeyOptionsResponse(AuthModel):
    """WebAuthn options for navigator.credentials, as the browser takes them."""

    options: dict[str, Any]


class AdminPasskeyRegisterRequest(AuthModel):
    name: str = Field(min_length=1, max_length=64)
    credential: dict[str, Any]


class AdminPasskeyLoginOptionsRequest(AuthModel):
    challenge: SecretStr = Field(min_length=10, max_length=128)


class AdminPasskeyLoginRequest(AdminPasskeyLoginOptionsRequest):
    credential: dict[str, Any]
