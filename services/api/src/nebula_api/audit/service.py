"""Read-only, filterable audit log listing for administrators."""

from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

from sqlalchemy import ColumnElement, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from nebula_api.db.engine import SessionFactory
from nebula_api.models.identity import AdminUser, Device, User
from nebula_api.models.operations import AuditChainCheckpoint, AuditLog
from nebula_api.models.topology import VPNServer

_MAX_LIMIT = 200


@dataclass(frozen=True, slots=True)
class AuditLogFilters:
    actor_kind: str | None = None
    target_kind: str | None = None
    event_code: str | None = None
    outcome: str | None = None
    actor_id: UUID | None = None
    target_id: UUID | None = None
    recorded_after: datetime | None = None
    recorded_before: datetime | None = None


@dataclass(frozen=True, slots=True)
class AuditLogEntry:
    id: UUID
    actor_kind: str
    actor_id: UUID | None
    target_kind: str
    target_id: UUID
    event_code: str
    outcome: str
    reason_code: str | None
    request_id: UUID | None
    recorded_at: datetime


@dataclass(frozen=True, slots=True)
class AuditLogPage:
    items: list[AuditLogEntry]
    total: int
    # What the panel shows for an id: a user's or admin's email, a
    # server's or device's name. Ids of anything since deleted are absent.
    names: dict[UUID, str] = field(default_factory=dict)


class AuditLogService:
    """Own read-only access to the append-only `audit_logs` table."""

    def __init__(self, session_factory: SessionFactory) -> None:
        self._session_factory = session_factory

    async def list_events(
        self, *, filters: AuditLogFilters, limit: int, offset: int
    ) -> AuditLogPage:
        bounded_limit = max(1, min(limit, _MAX_LIMIT))
        bounded_offset = max(0, offset)
        conditions = _conditions(filters)
        async with self._session_factory() as session:
            statement = select(AuditLog).where(*conditions)
            count_statement = select(func.count()).select_from(AuditLog).where(*conditions)
            statement = (
                statement.order_by(AuditLog.recorded_at.desc())
                .limit(bounded_limit)
                .offset(bounded_offset)
            )
            rows = (await session.scalars(statement)).all()
            total = await session.scalar(count_statement)
            names = await _names(session, rows)
        return AuditLogPage(items=[audit_entry(row) for row in rows], total=total or 0, names=names)

    async def latest_checkpoint(self) -> tuple[str, int, datetime] | None:
        """The newest prune checkpoint: head hash, events folded, and until."""

        async with self._session_factory() as session:
            row = await session.scalar(
                select(AuditChainCheckpoint).order_by(AuditChainCheckpoint.until.desc()).limit(1)
            )
        return None if row is None else (row.head, row.event_count, row.until)

    async def export_events(
        self, *, until: datetime, since: datetime | None = None
    ) -> AsyncIterator[AuditLogEntry]:
        """Every event recorded in [since, until), oldest first, in a fixed
        order, streamed: the whole log never sits in memory (AUD-009)."""

        conditions = [AuditLog.recorded_at < until]
        if since is not None:
            conditions.append(AuditLog.recorded_at >= since)
        async with self._session_factory() as session:
            # The 5-second limit is for requests; a large log takes longer.
            await session.execute(text("SET LOCAL statement_timeout = '600s'"))
            rows = await session.stream_scalars(
                select(AuditLog)
                .where(*conditions)
                .order_by(AuditLog.recorded_at, AuditLog.id)
                .execution_options(yield_per=1000)
            )
            async for row in rows:
                yield audit_entry(row)


_NAMED = {
    "user": (User.id, User.email),
    "admin": (AdminUser.id, AdminUser.email),
    "vpn_server": (VPNServer.id, VPNServer.display_name),
    "device": (Device.id, Device.name),
}


async def _names(session: AsyncSession, rows: Sequence[AuditLog]) -> dict[UUID, str]:
    """One lookup per kind on the page, not one per row."""

    wanted: dict[str, set[UUID]] = {}
    for row in rows:
        if row.actor_id is not None:
            wanted.setdefault(row.actor_kind, set()).add(row.actor_id)
        wanted.setdefault(row.target_kind, set()).add(row.target_id)
    names: dict[UUID, str] = {}
    for kind, ids in wanted.items():
        if kind not in _NAMED:
            continue
        id_column, name_column = _NAMED[kind]
        result = await session.execute(select(id_column, name_column).where(id_column.in_(ids)))
        names.update(
            {
                row_id: "Deleted account" if name.endswith("@deleted.invalid") else name
                for row_id, name in result.all()
            }
        )
    return names


def _conditions(filters: AuditLogFilters) -> list[ColumnElement[bool]]:
    conditions: list[ColumnElement[bool]] = []
    if filters.actor_kind is not None:
        conditions.append(AuditLog.actor_kind == filters.actor_kind)
    if filters.target_kind is not None:
        conditions.append(AuditLog.target_kind == filters.target_kind)
    if filters.event_code is not None:
        conditions.append(AuditLog.event_code == filters.event_code)
    if filters.outcome is not None:
        conditions.append(AuditLog.outcome == filters.outcome)
    if filters.actor_id is not None:
        conditions.append(AuditLog.actor_id == filters.actor_id)
    if filters.target_id is not None:
        conditions.append(AuditLog.target_id == filters.target_id)
    if filters.recorded_after is not None:
        conditions.append(AuditLog.recorded_at >= filters.recorded_after)
    if filters.recorded_before is not None:
        conditions.append(AuditLog.recorded_at <= filters.recorded_before)
    return conditions


def audit_entry(row: AuditLog) -> AuditLogEntry:
    return AuditLogEntry(
        id=row.id,
        actor_kind=row.actor_kind,
        actor_id=row.actor_id,
        target_kind=row.target_kind,
        target_id=row.target_id,
        event_code=row.event_code,
        outcome=row.outcome,
        reason_code=row.reason_code,
        request_id=row.request_id,
        recorded_at=row.recorded_at,
    )
