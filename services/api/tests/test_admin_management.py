"""Owners manage the other admins: service rules and the HTTP surface."""

import asyncio
from collections.abc import Iterable
from datetime import UTC, datetime, timedelta
from typing import Any, cast
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from nebula_api.admin_management import (
    AdminManagementRejected,
    AdminManagementService,
    AdminSummary,
    InvitedAdmin,
    router,
)
from nebula_api.auth.admin_service import AdminAuthService, AdminPrincipal
from nebula_api.auth.http import install_auth_http_safeguards
from nebula_api.auth.redis_state import AdminSessionRecord, AuthStateUnavailable, RedisAuthState
from nebula_api.db.engine import SessionFactory
from nebula_api.models.identity import AdminUser
from nebula_api.models.operations import AuditLog
from nebula_api.models.types import AdminRole, AdminState
from nebula_api.settings import Settings

NOW = datetime(2026, 11, 4, 12, 0, tzinfo=UTC)
OWNER_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
OTHER_ID = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
SESSION_ID = UUID("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
ORIGIN = "http://localhost:3000"


def run(coro: Any) -> Any:
    return asyncio.run(coro)


def admin(
    admin_id: UUID = OTHER_ID,
    *,
    role: AdminRole = AdminRole.OPERATOR,
    state: AdminState = AdminState.ACTIVE,
) -> AdminUser:
    row = AdminUser(
        id=admin_id,
        email="ops@example.com",
        email_normalized="ops@example.com",
        username=None,
        username_normalized=None,
        password_hash="x",  # noqa: S106 - test fixture
        role=role,
        state=state,
    )
    row.created_at = NOW
    row.disabled_at = None
    row.sessions_valid_after = None
    return row


class Rows:
    def __init__(self, values: Iterable[object]) -> None:
        self.values = list(values)

    def all(self) -> list[object]:
        return self.values


class Session:
    def __init__(
        self,
        *,
        scalar: Iterable[object] = (),
        scalars: Iterable[Iterable[object]] = (),
        get: object = None,
    ) -> None:
        self.scalar_values = list(scalar)
        self.scalars_values = [list(v) for v in scalars]
        self.get_value = get
        self.added: list[object] = []
        self.commits = 0

    async def __aenter__(self) -> "Session":
        return self

    async def __aexit__(self, *_: object) -> None:
        return None

    async def scalar(self, _statement: object) -> Any:
        return self.scalar_values.pop(0)

    async def scalars(self, _statement: object) -> Rows:
        return Rows(self.scalars_values.pop(0))

    async def get(self, _model: object, _key: object) -> Any:
        return self.get_value

    def add(self, row: object) -> None:
        self.added.append(row)

    async def flush(self) -> None:
        return None

    async def commit(self) -> None:
        self.commits += 1

    def audits(self) -> list[AuditLog]:
        return [row for row in self.added if isinstance(row, AuditLog)]


class Redis:
    def __init__(self, records: list[AdminSessionRecord] | None = None) -> None:
        self.records = records or []
        self.revoked: list[tuple[UUID, UUID]] = []
        self.revoke_result = True

    async def list_admin_sessions(self, _admin_id: UUID) -> list[AdminSessionRecord]:
        return self.records

    async def revoke_admin_session_by_id(self, admin_id: UUID, session_id: UUID) -> bool:
        self.revoked.append((admin_id, session_id))
        return self.revoke_result


def service(session: Session, redis: Redis | None = None) -> AdminManagementService:
    return AdminManagementService(
        cast(SessionFactory, lambda: session),
        cast(RedisAuthState, redis or Redis()),
        clock=lambda: NOW,
    )


def record(created: datetime, session_id: UUID = SESSION_ID) -> AdminSessionRecord:
    return AdminSessionRecord(
        admin_id=OTHER_ID,
        session_id=session_id,
        mfa_method="totp",
        created_at=created,
        last_seen_at=created,
        absolute_expires_at=created + timedelta(hours=8),
        step_up_at=None,
    )


# --- service ----------------------------------------------------------------


def test_list_marks_who_has_an_authenticator() -> None:
    other = admin()
    session = Session(scalars=[[admin(OWNER_ID, role=AdminRole.OWNER), other], [OWNER_ID]])
    admins = run(service(session).list_admins())
    assert [(a.admin_id, a.has_authenticator) for a in admins] == [
        (OWNER_ID, True),
        (OTHER_ID, False),
    ]


def test_invite_makes_an_active_admin_with_a_one_time_password() -> None:
    session = Session(scalar=[None])
    invited = run(
        service(session).invite(
            actor_id=OWNER_ID, email=" New@Example.com ", username="newbie", role=AdminRole.AUDITOR
        )
    )
    row = next(r for r in session.added if isinstance(r, AdminUser))
    assert row.email_normalized == "new@example.com"
    assert row.username_normalized == "newbie"
    assert row.role == AdminRole.AUDITOR and row.state == AdminState.ACTIVE
    assert row.password_hash != invited.temporary_password
    assert len(invited.temporary_password) >= 20
    assert "temporary_password=<redacted>" in repr(invited)
    assert session.audits()[0].reason_code == "admin_invited"
    assert session.commits == 1


def test_invite_refuses_an_email_or_username_in_use() -> None:
    session = Session(scalar=[OTHER_ID])
    with pytest.raises(AdminManagementRejected, match="exists"):
        run(
            service(session).invite(
                actor_id=OWNER_ID, email="ops@example.com", username=None, role=AdminRole.OPERATOR
            )
        )
    assert session.commits == 0


def test_role_change_ends_the_old_sessions() -> None:
    other = admin()
    session = Session(scalar=[other, None])
    summary = run(
        service(session).change_role(actor_id=OWNER_ID, admin_id=OTHER_ID, role=AdminRole.OWNER)
    )
    assert summary.role == AdminRole.OWNER
    assert other.sessions_valid_after == NOW
    assert session.audits()[0].reason_code == "admin_role_changed"


def test_same_role_writes_nothing() -> None:
    session = Session(scalar=[admin(), None])
    run(service(session).change_role(actor_id=OWNER_ID, admin_id=OTHER_ID, role=AdminRole.OPERATOR))
    assert session.audits() == []


def test_owner_cannot_change_or_disable_themselves() -> None:
    session = Session()
    with pytest.raises(AdminManagementRejected) as raised:
        run(service(session).set_disabled(actor_id=OWNER_ID, admin_id=OWNER_ID, disabled=True))
    assert raised.value.status_code == 403
    with pytest.raises(AdminManagementRejected):
        run(
            service(session).change_role(
                actor_id=OWNER_ID, admin_id=OWNER_ID, role=AdminRole.AUDITOR
            )
        )


def test_unknown_admin_is_404() -> None:
    with pytest.raises(AdminManagementRejected) as raised:
        run(
            service(Session(scalar=[None])).set_disabled(
                actor_id=OWNER_ID, admin_id=OTHER_ID, disabled=True
            )
        )
    assert raised.value.status_code == 404


def test_disable_and_reactivate() -> None:
    other = admin()
    session = Session(scalar=[other, OTHER_ID])
    summary = run(
        service(session).set_disabled(actor_id=OWNER_ID, admin_id=OTHER_ID, disabled=True)
    )
    assert summary.state == AdminState.DISABLED and summary.has_authenticator
    assert other.disabled_at == NOW and other.sessions_valid_after == NOW
    session = Session(scalar=[other, None])
    run(service(session).set_disabled(actor_id=OWNER_ID, admin_id=OTHER_ID, disabled=False))
    assert other.state == AdminState.ACTIVE and other.disabled_at is None
    assert session.audits()[0].reason_code == "admin_reactivated"


def test_sessions_hide_ones_sign_in_no_longer_accepts() -> None:
    other = admin()
    other.sessions_valid_after = NOW
    redis = Redis([record(NOW - timedelta(minutes=5)), record(NOW + timedelta(minutes=1))])
    shown = run(service(Session(get=other), redis).sessions(OTHER_ID))
    assert [r.created_at for r in shown] == [NOW + timedelta(minutes=1)]


def test_sessions_of_an_unknown_admin_is_404() -> None:
    with pytest.raises(AdminManagementRejected):
        run(service(Session(get=None)).sessions(OTHER_ID))


def test_end_one_session_audits_it() -> None:
    redis = Redis()
    session = Session()
    run(
        service(session, redis).end_session(
            actor_id=OWNER_ID, admin_id=OTHER_ID, session_id=SESSION_ID
        )
    )
    assert redis.revoked == [(OTHER_ID, SESSION_ID)]
    assert session.audits()[0].event_code == "session_revoked"


def test_end_a_session_already_gone() -> None:
    redis = Redis()
    redis.revoke_result = False
    with pytest.raises(AdminManagementRejected, match="already ended"):
        run(
            service(Session(), redis).end_session(
                actor_id=OWNER_ID, admin_id=OTHER_ID, session_id=SESSION_ID
            )
        )


def test_end_all_sessions() -> None:
    other = admin()
    session = Session(scalar=[other])
    run(service(session).end_all_sessions(actor_id=OWNER_ID, admin_id=OTHER_ID))
    assert other.sessions_valid_after == NOW
    assert session.audits()[0].reason_code == "admin_sessions_ended"


# --- HTTP ---------------------------------------------------------------------


class FakeAuth:
    def __init__(self, role: AdminRole = AdminRole.OWNER, step_up: bool = True) -> None:
        self.role = role
        self.step_up = step_up

    async def principal(self, _token: str) -> AdminPrincipal:
        return AdminPrincipal(OWNER_ID, SESSION_ID, self.role, self.step_up, "totp")

    async def validate_and_rotate_csrf(self, _s: str, _c: str) -> str:
        return "v1.csrf-replacement"


def summary(admin_id: UUID = OTHER_ID, state: AdminState = AdminState.ACTIVE) -> AdminSummary:
    return AdminSummary(
        admin_id, "ops@example.com", None, AdminRole.OPERATOR, state, True, NOW, None
    )


class FakeService:
    def __init__(self) -> None:
        self.error: Exception | None = None
        self.calls: list[str] = []

    def _check(self, name: str) -> None:
        self.calls.append(name)
        if self.error is not None:
            raise self.error

    async def list_admins(self) -> list[AdminSummary]:
        return [summary(OWNER_ID), summary()]

    async def invite(self, **_: object) -> InvitedAdmin:
        self._check("invite")
        return InvitedAdmin(summary(), "one-time-password-canary")

    async def change_role(self, **_: object) -> AdminSummary:
        self._check("role")
        return summary()

    async def set_disabled(self, *, disabled: bool, **_: object) -> AdminSummary:
        self._check("disable" if disabled else "reactivate")
        return summary(state=AdminState.DISABLED if disabled else AdminState.ACTIVE)

    async def sessions(self, _admin_id: UUID) -> list[AdminSessionRecord]:
        self._check("sessions")
        return [record(NOW), record(NOW, uuid4())]

    async def end_session(self, **_: object) -> None:
        self._check("end")

    async def end_all_sessions(self, **_: object) -> None:
        self._check("end-all")


def client(auth: FakeAuth | None = None, svc: FakeService | None = None) -> TestClient:
    settings = Settings(env="test")
    app = FastAPI()
    app.state.settings = settings
    app.state.admin_auth_service = cast(AdminAuthService, auth or FakeAuth())
    if svc is not None:
        app.state.admin_management_service = svc
    install_auth_http_safeguards(app, settings)
    app.include_router(router)
    test_client = TestClient(app)
    test_client.cookies.set(settings.admin_cookie_name, "v1.session-canary")
    test_client.cookies.set(settings.admin_csrf_cookie_name, "v1.csrf-canary")
    return test_client


HEADERS = {"Origin": ORIGIN, "X-CSRF-Token": "v1.csrf-canary"}


def test_list_is_for_owners_only() -> None:
    with client(FakeAuth(AdminRole.OPERATOR), FakeService()) as c:
        assert c.get("/v1/admin/admins/").status_code == 403
    with client(svc=FakeService()) as c:
        body = c.get("/v1/admin/admins/").json()
    assert [item["is_you"] for item in body["items"]] == [True, False]


def test_without_the_service_it_says_unavailable() -> None:
    with client() as c:
        assert c.get("/v1/admin/admins/").status_code == 503


def test_invite_needs_step_up_and_returns_the_password_once() -> None:
    with client(FakeAuth(step_up=False), FakeService()) as c:
        refused = c.post(
            "/v1/admin/admins/", headers=HEADERS, json={"email": "a@b.c", "role": "auditor"}
        )
    assert refused.json()["detail"] == "step_up_required"
    with client(svc=FakeService()) as c:
        made = c.post(
            "/v1/admin/admins/", headers=HEADERS, json={"email": "a@b.c", "role": "auditor"}
        )
    assert made.status_code == 201
    assert made.json()["temporary_password"] == "one-time-password-canary"  # noqa: S105 - test fixture


def test_invite_refusals_reach_the_owner() -> None:
    svc = FakeService()
    svc.error = AdminManagementRejected("An admin with this email or username exists.")
    with client(svc=svc) as c:
        response = c.post(
            "/v1/admin/admins/", headers=HEADERS, json={"email": "a@b.c", "role": "auditor"}
        )
    assert response.status_code == 409 and "exists" in response.json()["detail"]
    svc.error = ValueError("email address is invalid")
    with client(svc=svc) as c:
        response = c.post(
            "/v1/admin/admins/", headers=HEADERS, json={"email": "a@b.c", "role": "auditor"}
        )
    assert response.status_code == 422


@pytest.mark.parametrize(
    ("path", "body", "call"),
    [
        (f"/v1/admin/admins/{OTHER_ID}/role", {"role": "owner"}, "role"),
        (f"/v1/admin/admins/{OTHER_ID}/disable", {}, "disable"),
        (f"/v1/admin/admins/{OTHER_ID}/reactivate", {}, "reactivate"),
        (f"/v1/admin/admins/{OTHER_ID}/sessions/{SESSION_ID}/end", {}, "end"),
        (f"/v1/admin/admins/{OTHER_ID}/sessions/end-all", {}, "end-all"),
    ],
)
def test_mutations(path: str, body: dict[str, str], call: str) -> None:
    svc = FakeService()
    with client(svc=svc) as c:
        ok = c.post(path, headers=HEADERS, json=body)
    assert ok.status_code in (200, 204) and svc.calls == [call]
    svc.error = AdminManagementRejected(
        "Change your own account on the Security page.", status_code=403
    )
    with client(svc=svc) as c:
        refused = c.post(path, headers=HEADERS, json=body)
    assert refused.status_code == 403 and "Security page" in refused.json()["detail"]
    with client(FakeAuth(AdminRole.OPERATOR), FakeService()) as c:
        assert c.post(path, headers=HEADERS, json=body).status_code == 403


def test_sessions_list_marks_this_one() -> None:
    with client(svc=FakeService()) as c:
        items = c.get(f"/v1/admin/admins/{OTHER_ID}/sessions").json()["items"]
    assert [item["is_this_one"] for item in items] == [True, False]


def test_sessions_when_redis_is_down() -> None:
    svc = FakeService()
    svc.error = AuthStateUnavailable("down")
    with client(svc=svc) as c:
        assert c.get(f"/v1/admin/admins/{OTHER_ID}/sessions").status_code == 503
