"""Hash-chained audit log export, and its verification.

Each exported line is one audit event plus `prev` (the previous line's hash)
and `hash` = SHA-256 of `prev` followed by the event's canonical JSON. The
last line names the head hash and the count. Changing, removing, reordering
or inserting an event anywhere breaks every hash after it, so an export kept
off the server proves what the log held: a later export must contain it
unchanged (`verify_extends`).

Retention deletes the oldest events. Before it does, it stores where the
chain stood after them (a checkpoint: head hash and count); an export then
opens with that checkpoint and chains on from it, so an export kept from
before the prune still verifies against one made after (audit AUD-009).
"""

import hashlib
import json
from collections.abc import AsyncIterable, AsyncIterator, Iterable, Iterator
from dataclasses import dataclass
from datetime import datetime

from nebula_api.audit.service import AuditLogEntry

FORMAT = "nebula-audit-chain/1"
GENESIS = "0" * 64


class AuditChainError(ValueError):
    """The export is not an intact chain, or does not extend the older one."""


@dataclass(frozen=True, slots=True)
class ChainStart:
    """Where the chain stands before the first exported event."""

    head: str = GENESIS
    count: int = 0


_FROM_GENESIS = ChainStart()


@dataclass(frozen=True, slots=True)
class ChainSummary:
    count: int
    head: str
    until: str
    hashes: tuple[str, ...]
    # Events folded into a checkpoint before the first exported one.
    start: ChainStart = ChainStart()


def _canonical(entry: AuditLogEntry) -> dict[str, str | None]:
    def text(value: object) -> str | None:
        return None if value is None else str(value)

    return {
        "id": str(entry.id),
        "recorded_at": entry.recorded_at.isoformat(),
        "actor_kind": entry.actor_kind,
        "actor_id": text(entry.actor_id),
        "target_kind": entry.target_kind,
        "target_id": str(entry.target_id),
        "event_code": entry.event_code,
        "outcome": entry.outcome,
        "reason_code": entry.reason_code,
        "request_id": text(entry.request_id),
    }


def _dump(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _link(prev: str, event: dict[str, str | None]) -> str:
    return hashlib.sha256((prev + _dump(event)).encode()).hexdigest()


def _event_line(prev: str, entry: AuditLogEntry) -> tuple[str, str]:
    event = _canonical(entry)
    digest = _link(prev, event)
    return digest, _dump({**event, "prev": prev, "hash": digest}) + "\n"


def _opening(start: ChainStart) -> str:
    return _dump({"format": FORMAT, "checkpoint": start.head, "skipped": start.count}) + "\n"


def _closing(prev: str, count: int, until: datetime) -> str:
    return (
        _dump({"format": FORMAT, "count": count, "head": prev, "until": until.isoformat()}) + "\n"
    )


def chain_lines(
    entries: Iterable[AuditLogEntry], *, until: datetime, start: ChainStart = _FROM_GENESIS
) -> Iterator[str]:
    """Newline-terminated export lines for `entries`, oldest first."""

    if start.count:
        yield _opening(start)
    prev, count = start.head, 0
    for entry in entries:
        prev, line = _event_line(prev, entry)
        count += 1
        yield line
    yield _closing(prev, count, until)


async def chain_lines_async(
    entries: AsyncIterable[AuditLogEntry], *, until: datetime, start: ChainStart = _FROM_GENESIS
) -> AsyncIterator[str]:
    """chain_lines over a streamed query."""

    if start.count:
        yield _opening(start)
    prev, count = start.head, 0
    async for entry in entries:
        prev, line = _event_line(prev, entry)
        count += 1
        yield line
    yield _closing(prev, count, until)


def advance(start: ChainStart, entries: Iterable[AuditLogEntry]) -> ChainStart:
    """The checkpoint after `entries` (oldest first) are folded into `start`."""

    head, count = start.head, start.count
    for entry in entries:
        head = _link(head, _canonical(entry))
        count += 1
    return ChainStart(head, count)


def verify(lines: Iterable[str]) -> ChainSummary:
    """Recompute every link; raise AuditChainError on the first break."""

    start = ChainStart()
    prev, hashes = GENESIS, []
    trailer: dict[str, object] | None = None
    for number, line in enumerate((line for line in lines if line.strip()), start=1):
        if trailer is not None:
            raise AuditChainError(f"line {number}: events after the closing line")
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise AuditChainError(f"line {number}: not JSON") from error
        if not isinstance(record, dict):
            raise AuditChainError(f"line {number}: not an object")
        if "checkpoint" in record:
            head, skipped = record.get("checkpoint"), record.get("skipped")
            if (
                number != 1
                or record.get("format") != FORMAT
                or not isinstance(head, str)
                or not isinstance(skipped, int)
                or skipped < 1
            ):
                raise AuditChainError(f"line {number}: a misplaced or malformed checkpoint")
            start, prev = ChainStart(head, skipped), head
            continue
        if "format" in record:
            trailer = record
            continue
        claimed_prev, claimed = record.pop("prev", None), record.pop("hash", None)
        if claimed_prev != prev or claimed != _link(prev, record):
            raise AuditChainError(
                f"line {number}: the chain breaks here (event {record.get('id')})"
            )
        prev = claimed
        hashes.append(claimed)
    if trailer is None or trailer.get("format") != FORMAT:
        raise AuditChainError("no closing line: the export is cut short")
    if trailer.get("count") != len(hashes) or trailer.get("head") != prev:
        raise AuditChainError("the closing line does not match the events")
    return ChainSummary(len(hashes), prev, str(trailer.get("until")), tuple(hashes), start)


def verify_extends(older: Iterable[str], newer: Iterable[str]) -> ChainSummary:
    """Both exports intact, and the newer one holds the older one unchanged.

    Events are numbered from the start of the log, checkpoints included, so
    one comparison at the older export's last event settles it: equal hashes
    there mean every event up to it is the same, pruned or not.
    """

    old, new = verify(older), verify(newer)
    if not old.count:
        return new
    last = old.start.count + old.count - 1
    first = new.start.count
    if first - 1 <= last < first + new.count:
        held = new.start.head if last == first - 1 else new.hashes[last - first]
        if held == old.head:
            return new
    elif last < first - 1:
        raise AuditChainError(
            "the newer export's checkpoint is past every event of the older one; "
            "compare it with an export made after the older one"
        )
    raise AuditChainError(
        f"the newer export does not contain the older one's {old.count} events unchanged"
    )
