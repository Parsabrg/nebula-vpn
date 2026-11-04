# ruff: noqa: S105, S106 - test fixtures, not real secrets
"""Admin passkeys: added and removed on the Security page, used at sign-in.

The WebAuthn checks themselves are the `webauthn` library's; these pin the
rules around them: whose passkey, which challenge, once, and what is kept.
"""

import asyncio
import json
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from typing import Any, cast
from uuid import UUID, uuid4

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi import FastAPI
from fastapi.testclient import TestClient

import nebula_api.auth.admin_service as admin_service_module
from nebula_api.auth.admin_routes import router
from nebula_api.auth.admin_service import (
    AdminAuthService,
    AdminCredentialRejected,
    AdminPasskeySummary,
)
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.auth.key_material import AuthKeyMaterial
from nebula_api.auth.redis_state import (
    AdminSessionRecord,
    ConsumedPreAuth,
    IssuedAdminSession,
    LockoutState,
    RedisAuthState,
)
from nebula_api.auth.user_service import AuthenticationRejected
from nebula_api.db.engine import SessionFactory
from nebula_api.models.identity import AdminPasskey, AdminUser
from nebula_api.models.operations import AuditLog
from nebula_api.models.types import AdminRole, AdminState
from nebula_api.settings import Settings

NOW = datetime(2026, 11, 4, 12, 0, tzinfo=UTC)
ADMIN_ID = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
SESSION_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
PASSKEY_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
ORIGIN = "https://panel.example.test"


def run(coro: Any) -> Any:
    return asyncio.run(coro)


def make_admin() -> AdminUser:
    return AdminUser(
        id=ADMIN_ID,
        email="owner@example.com",
        email_normalized="owner@example.com",
        password_hash="x",
        role=AdminRole.OWNER,
        state=AdminState.ACTIVE,
        sessions_valid_after=None,
    )


def make_passkey() -> AdminPasskey:
    row = AdminPasskey(
        id=PASSKEY_ID,
        admin_user_id=ADMIN_ID,
        credential_id=b"cred-1",
        public_key=b"key",
        sign_count=3,
        name="Laptop",
    )
    row.created_at = NOW
    row.last_used_at = None
    return row


class Rows:
    def __init__(self, values: list[object]) -> None:
        self.values = values

    def all(self) -> list[object]:
        return self.values


class Db:
    """Answers by what is selected, so call order does not matter."""

    def __init__(self) -> None:
        self.admin: AdminUser | None = make_admin()
        self.passkeys: list[AdminPasskey] = [make_passkey()]
        self.added: list[object] = []
        self.deleted: list[object] = []
        self.commits = 0

    async def __aenter__(self) -> "Db":
        return self

    async def __aexit__(self, *_: object) -> None:
        return None

    async def scalar(self, statement: Any) -> Any:
        column = statement.column_descriptions[0]
        if column["entity"] is AdminUser:
            return self.admin
        if column["name"] == "id":
            wanted = statement.whereclause.right.value
            return next((p.id for p in self.passkeys if p.credential_id == wanted), None)
        if column["name"] == "AdminPasskey":
            values = [c.right.value for c in statement.whereclause.clauses]
            return next(
                (p for p in self.passkeys if p.id in values or p.credential_id in values), None
            )
        raise AssertionError(column)

    async def scalars(self, statement: Any) -> Rows:
        column = statement.column_descriptions[0]
        if column["name"] == "credential_id":
            return Rows([p.credential_id for p in self.passkeys])
        return Rows(list(self.passkeys))

    def add(self, row: object) -> None:
        self.added.append(row)

    async def delete(self, row: object) -> None:
        self.deleted.append(row)

    async def flush(self) -> None:
        return None

    async def commit(self) -> None:
        self.commits += 1

    def audits(self) -> list[AuditLog]:
        return [r for r in self.added if isinstance(r, AuditLog)]


class Redis:
    def __init__(self) -> None:
        self.stepped_up = True
        self.peeked: UUID | None = ADMIN_ID
        self.consumed = True
        self.challenges: dict[str, bytes] = {}
        self.failures = 0
        self.cleared: list[str] = []
        self.issued: list[str] = []

    async def get_admin_session(self, _token: str, *, idle_ttl: timedelta) -> AdminSessionRecord:
        return AdminSessionRecord(
            ADMIN_ID,
            SESSION_ID,
            "totp",
            NOW,
            NOW,
            NOW + timedelta(hours=8),
            NOW if self.stepped_up else None,
        )

    async def peek_preauth(self, _token: str, *, purpose: str, context: str) -> UUID | None:
        assert purpose == "login" and context
        return self.peeked

    async def put_webauthn_challenge(
        self, subject: str, *, admin_id: UUID, challenge: bytes, ttl_seconds: int
    ) -> None:
        assert admin_id == ADMIN_ID and 0 < ttl_seconds <= 600
        self.challenges[subject] = challenge

    async def take_webauthn_challenge(self, subject: str, *, admin_id: UUID) -> bytes | None:
        return self.challenges.pop(subject, None)

    async def rate_limit(self, *_: object, **__: object) -> bool:
        return True

    async def consume_preauth(self, _token: str, *, purpose: str, context: str) -> Any:
        return ConsumedPreAuth(ADMIN_ID, "login") if self.consumed else None

    async def record_admin_failure(self, *_: object, **__: object) -> LockoutState:
        self.failures += 1
        return LockoutState(False, 0)

    async def clear_admin_failures(self, account: str) -> None:
        self.cleared.append(account)

    async def issue_admin_session(self, *, mfa_method: str, **_: object) -> IssuedAdminSession:
        self.issued.append(mfa_method)
        record = AdminSessionRecord(
            ADMIN_ID, uuid4(), cast(Any, mfa_method), NOW, NOW, NOW + timedelta(hours=8), None
        )
        return IssuedAdminSession("v1.session", "v1.csrf", record)

    async def revoke_admin_session(self, _token: str) -> None:
        return None


def keys() -> AuthKeyMaterial:
    private = Ed25519PrivateKey.generate()
    return AuthKeyMaterial(
        private, {"v1": private.public_key()}, {1: b"p" * 32}, {1: b"m" * 32}, {1: b"x" * 32}
    )


def make_service(db: Db, redis: Redis) -> AdminAuthService:
    return AdminAuthService(
        cast(SessionFactory, lambda: db),
        cast(RedisAuthState, redis),
        keys(),
        Settings(env="test", allowed_origins=ORIGIN),
        clock=lambda: NOW,
    )


# --- adding and removing ---------------------------------------------------


def test_registration_options_name_the_panel_and_skip_passkeys_already_added() -> None:
    db, redis = Db(), Redis()
    options = json.loads(
        run(make_service(db, redis).passkey_registration_options(session_token="t"))
    )
    assert options["rp"]["id"] == "panel.example.test"
    assert options["user"]["name"] == "owner@example.com"
    assert len(options["excludeCredentials"]) == 1
    assert f"register:{SESSION_ID}" in redis.challenges


def test_adding_a_passkey_needs_a_fresh_code() -> None:
    redis = Redis()
    redis.stepped_up = False
    with pytest.raises(AuthenticationRejected):
        run(make_service(Db(), redis).passkey_registration_options(session_token="t"))


def test_a_verified_passkey_is_kept_and_audited(monkeypatch: pytest.MonkeyPatch) -> None:
    db, redis = Db(), Redis()
    db.passkeys = []
    redis.challenges[f"register:{SESSION_ID}"] = b"challenge"
    seen: dict[str, Any] = {}

    def verify(**kwargs: Any) -> SimpleNamespace:
        seen.update(kwargs)
        return SimpleNamespace(credential_id=b"new", credential_public_key=b"pk", sign_count=0)

    monkeypatch.setattr(admin_service_module, "verify_registration_response", verify)
    summary = run(
        make_service(db, redis).register_passkey(
            session_token="t", name=" Phone ", credential={"id": "x"}, request_id=uuid4()
        )
    )
    assert summary.name == "Phone" and summary.created_at == NOW
    assert seen["expected_challenge"] == b"challenge"
    assert seen["expected_origin"] == [ORIGIN]
    row = next(r for r in db.added if isinstance(r, AdminPasskey))
    assert (row.credential_id, row.public_key) == (b"new", b"pk")
    assert db.audits()[0].reason_code == "passkey_added"


def test_a_passkey_cannot_be_added_twice_or_without_its_challenge(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    db, redis = Db(), Redis()
    service = make_service(db, redis)
    with pytest.raises(AdminCredentialRejected, match="ran out of time"):
        run(
            service.register_passkey(session_token="t", name="a", credential={}, request_id=uuid4())
        )
    monkeypatch.setattr(
        admin_service_module,
        "verify_registration_response",
        lambda **_: SimpleNamespace(
            credential_id=b"cred-1", credential_public_key=b"", sign_count=0
        ),
    )
    redis.challenges[f"register:{SESSION_ID}"] = b"c"
    with pytest.raises(AdminCredentialRejected, match="already added"):
        run(
            service.register_passkey(session_token="t", name="a", credential={}, request_id=uuid4())
        )


def test_a_registration_the_library_refuses_is_refused(monkeypatch: pytest.MonkeyPatch) -> None:
    redis = Redis()
    redis.challenges[f"register:{SESSION_ID}"] = b"c"

    def refuse(**_: Any) -> None:
        raise ValueError("bad")

    monkeypatch.setattr(admin_service_module, "verify_registration_response", refuse)
    with pytest.raises(AdminCredentialRejected, match="could not be checked"):
        run(
            make_service(Db(), redis).register_passkey(
                session_token="t", name="a", credential={}, request_id=uuid4()
            )
        )


def test_list_and_remove() -> None:
    db = Db()
    service = make_service(db, Redis())
    assert [p.name for p in run(service.list_passkeys(ADMIN_ID))] == ["Laptop"]
    run(service.remove_passkey(session_token="t", passkey_id=PASSKEY_ID, request_id=uuid4()))
    assert db.deleted and db.audits()[0].reason_code == "passkey_removed"
    db.passkeys = []
    with pytest.raises(AdminCredentialRejected):
        run(service.remove_passkey(session_token="t", passkey_id=PASSKEY_ID, request_id=uuid4()))


# --- signing in --------------------------------------------------------------


def test_login_options_leave_the_code_path_open() -> None:
    redis = Redis()
    options = json.loads(
        run(make_service(Db(), redis).passkey_login_options(challenge="v1.c", network_prefix="n"))
    )
    assert options["rpId"] == "panel.example.test"
    assert len(options["allowCredentials"]) == 1
    assert "login:v1.c" in redis.challenges


def test_login_options_without_a_passkey_or_a_challenge() -> None:
    db, redis = Db(), Redis()
    db.passkeys = []
    with pytest.raises(AdminCredentialRejected, match="Use the code"):
        run(make_service(db, redis).passkey_login_options(challenge="v1.c", network_prefix="n"))
    redis.peeked = None
    with pytest.raises(AuthenticationRejected):
        run(make_service(db, redis).passkey_login_options(challenge="v1.c", network_prefix="n"))


def _login(db: Db, redis: Redis, raw_id: str = "Y3JlZC0x") -> Any:
    return run(
        make_service(db, redis).verify_passkey_login(
            challenge="v1.c",
            credential={"rawId": raw_id},
            network_prefix="n",
            request_id=uuid4(),
        )
    )


def test_a_passkey_signs_in(monkeypatch: pytest.MonkeyPatch) -> None:
    db, redis = Db(), Redis()
    redis.challenges["login:v1.c"] = b"expected"
    seen: dict[str, Any] = {}

    def verify(**kwargs: Any) -> SimpleNamespace:
        seen.update(kwargs)
        return SimpleNamespace(new_sign_count=4)

    monkeypatch.setattr(admin_service_module, "verify_authentication_response", verify)
    authentication = _login(db, redis)
    assert authentication.session.session_token == "v1.session"
    assert redis.issued == ["passkey"] and redis.cleared == [str(ADMIN_ID)]
    assert seen["credential_current_sign_count"] == 3
    assert db.passkeys[0].sign_count == 4 and db.passkeys[0].last_used_at == NOW
    assert db.audits()[0].reason_code == "passkey"


def test_a_wrong_or_unknown_passkey_is_a_failed_sign_in(monkeypatch: pytest.MonkeyPatch) -> None:
    db, redis = Db(), Redis()
    redis.challenges["login:v1.c"] = b"expected"
    with pytest.raises(AuthenticationRejected):
        _login(db, redis, raw_id="dW5rbm93bg")  # "unknown"
    assert redis.failures == 1

    def refuse(**_: Any) -> None:
        raise ValueError("signature")

    monkeypatch.setattr(admin_service_module, "verify_authentication_response", refuse)
    redis.challenges["login:v1.c"] = b"expected"
    with pytest.raises(AuthenticationRejected):
        _login(db, redis)
    assert redis.failures == 2 and redis.issued == []


def test_no_prompt_was_opened_or_the_challenge_is_spent() -> None:
    db, redis = Db(), Redis()
    with pytest.raises(AuthenticationRejected):
        _login(db, redis)
    redis.consumed = False
    with pytest.raises(AuthenticationRejected):
        _login(db, redis)


def test_a_malformed_credential_id_is_refused(monkeypatch: pytest.MonkeyPatch) -> None:
    db, redis = Db(), Redis()
    redis.challenges["login:v1.c"] = b"expected"
    with pytest.raises(AuthenticationRejected):
        run(
            make_service(db, redis).verify_passkey_login(
                challenge="v1.c", credential={}, network_prefix="n", request_id=uuid4()
            )
        )


# --- HTTP ----------------------------------------------------------------------


class FakeService:
    def __init__(self) -> None:
        self.error: Exception | None = None

    def _check(self) -> None:
        if self.error is not None:
            raise self.error

    async def principal(self, _token: str) -> Any:
        from nebula_api.auth.admin_service import AdminPrincipal

        return AdminPrincipal(ADMIN_ID, SESSION_ID, AdminRole.OWNER, True, "passkey")

    async def validate_and_rotate_csrf(self, _s: str, _c: str) -> str:
        return "v1.csrf-next"

    async def list_passkeys(self, _admin_id: UUID) -> list[AdminPasskeySummary]:
        return [AdminPasskeySummary(PASSKEY_ID, "Laptop", NOW, None)]

    async def passkey_registration_options(self, **_: object) -> str:
        self._check()
        return '{"challenge": "abc"}'

    async def register_passkey(self, **_: object) -> AdminPasskeySummary:
        self._check()
        return AdminPasskeySummary(PASSKEY_ID, "Laptop", NOW, None)

    async def remove_passkey(self, **_: object) -> None:
        self._check()

    async def passkey_login_options(self, **_: object) -> str:
        self._check()
        return '{"challenge": "def"}'

    async def verify_passkey_login(self, **_: object) -> Any:
        self._check()
        return SimpleNamespace(session=IssuedAdminSession("v1.session", "v1.csrf", cast(Any, None)))


def client(service: FakeService) -> TestClient:
    settings = Settings(env="test", allowed_origins=ORIGIN)
    app = FastAPI()
    app.state.settings = settings
    app.state.admin_auth_service = service
    install_auth_http_safeguards(app, settings)
    app.include_router(router)
    test_client = TestClient(app)
    test_client.cookies.set(settings.admin_cookie_name, "v1.session-canary")
    test_client.cookies.set(settings.admin_csrf_cookie_name, "v1.csrf-canary")
    return test_client


HEADERS = {"Origin": ORIGIN, "X-CSRF-Token": "v1.csrf-canary"}


def post(c: TestClient, path: str, body: dict[str, Any]) -> Any:
    # Each mutation rotates the CSRF cookie; put the one HEADERS carries back.
    name = Settings(env="test").admin_csrf_cookie_name
    c.cookies.delete(name)
    c.cookies.set(name, "v1.csrf-canary")
    return c.post(path, headers=HEADERS, json=body)


def test_routes_for_your_own_passkeys() -> None:
    service = FakeService()
    with client(service) as c:
        assert c.get("/v1/admin/auth/passkeys").json()["items"][0]["name"] == "Laptop"
        assert post(c, "/v1/admin/auth/passkeys/options", {}).json() == {
            "options": {"challenge": "abc"}
        }
        added = post(c, "/v1/admin/auth/passkeys", {"name": "Laptop", "credential": {}})
        assert added.json()["id"] == str(PASSKEY_ID)
        assert (post(c, f"/v1/admin/auth/passkeys/{PASSKEY_ID}/delete", {})).status_code == 204
        service.error = AdminCredentialRejected("This passkey is already added.")
        refused = post(c, "/v1/admin/auth/passkeys", {"name": "a", "credential": {}})
        assert refused.status_code == 409 and "already" in refused.json()["detail"]
        gone = post(c, f"/v1/admin/auth/passkeys/{PASSKEY_ID}/delete", {})
        assert gone.status_code == 404
        service.error = AuthenticationRejected()
        assert post(c, "/v1/admin/auth/passkeys/options", {}).status_code == 401


def test_routes_for_signing_in_with_a_passkey() -> None:
    service = FakeService()
    body = {"challenge": "v1.challenge-canary"}
    with client(service) as c:
        options = post(c, "/v1/admin/auth/mfa/passkey/options", body)
        assert options.json() == {"options": {"challenge": "def"}}
        signed_in = post(c, "/v1/admin/auth/mfa/passkey/verify", {**body, "credential": {}})
        assert signed_in.status_code == 200 and signed_in.json()["csrf_token"] == "v1.csrf"
        service.error = AdminCredentialRejected("No passkey is set up for this account.")
        assert post(c, "/v1/admin/auth/mfa/passkey/options", body).status_code == 409
        service.error = AuthenticationRejected()
        assert post(c, "/v1/admin/auth/mfa/passkey/options", body).status_code == 401
        assert (
            c.post(
                "/v1/admin/auth/mfa/passkey/verify",
                headers=HEADERS,
                json={**body, "credential": {}},
            ).status_code
            == 401
        )
