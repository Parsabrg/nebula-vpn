import json
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest

from nebula_api.audit.chain import (
    GENESIS,
    AuditChainError,
    ChainStart,
    advance,
    chain_lines,
    verify,
    verify_extends,
)
from nebula_api.audit.service import AuditLogEntry
from nebula_api.cli import main

NOW = datetime(2026, 10, 30, 12, 0, tzinfo=UTC)


def entry(minute: int, *, outcome: str = "success") -> AuditLogEntry:
    return AuditLogEntry(
        id=uuid4(),
        actor_kind="admin",
        actor_id=UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
        target_kind="user",
        target_id=uuid4(),
        event_code="user.disabled",
        outcome=outcome,
        reason_code=None,
        request_id=None,
        recorded_at=NOW + timedelta(minutes=minute),
    )


def export(entries: list[AuditLogEntry]) -> list[str]:
    return list(chain_lines(entries, until=NOW + timedelta(hours=1)))


def test_an_intact_export_verifies() -> None:
    lines = export([entry(1), entry(2), entry(3)])
    summary = verify(lines)
    assert summary.count == 3
    assert summary.head == json.loads(lines[2])["hash"]
    assert json.loads(lines[0])["prev"] == GENESIS


def test_an_empty_log_exports_and_verifies() -> None:
    summary = verify(export([]))
    assert (summary.count, summary.head) == (0, GENESIS)


@pytest.mark.parametrize(
    "tamper",
    [
        lambda lines: [lines[0].replace('"success"', '"failure"'), *lines[1:]],
        lambda lines: [lines[0], *lines[2:]],
        lambda lines: [lines[1], lines[0], *lines[2:]],
        lambda lines: lines[:-1],
        lambda lines: [*lines[:-1], lines[-1].replace('"count":3', '"count":2')],
        lambda lines: [*lines, lines[0]],
        lambda lines: ["not json", *lines],
        lambda lines: ["[1]", *lines],
    ],
    ids=["edited", "removed", "reordered", "cut-short", "count", "after-close", "garbage", "array"],
)
def test_any_change_is_caught(tamper) -> None:  # type: ignore[no-untyped-def]
    with pytest.raises(AuditChainError):
        verify(tamper(export([entry(1), entry(2), entry(3)])))


def test_a_newer_export_must_hold_the_older_one_unchanged() -> None:
    events = [entry(1), entry(2)]
    older = export(events)
    assert verify_extends(older, export([*events, entry(3)])).count == 3

    rewritten = [events[0], entry(2, outcome="failure"), entry(3)]
    with pytest.raises(AuditChainError, match="unchanged"):
        verify_extends(older, export(rewritten))
    with pytest.raises(AuditChainError, match="unchanged"):
        verify_extends(older, export(events[:1]))
    assert verify_extends(export([]), older).count == 2


def test_audit_verify_command(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    events = [entry(1), entry(2)]
    old, new = tmp_path / "old.jsonl", tmp_path / "new.jsonl"
    old.write_text("".join(export(events)), encoding="utf-8")
    new.write_text("".join(export([*events, entry(3)])), encoding="utf-8")

    assert main(["audit-verify", str(new)]) == 0
    assert "intact: 3 events" in capsys.readouterr().out
    assert main(["audit-verify", str(new), "--extends", str(old)]) == 0
    assert "contains" in capsys.readouterr().out

    with pytest.raises(SystemExit):
        main(["audit-verify", str(old), "--extends", str(new)])
    assert "unchanged" in capsys.readouterr().err
    with pytest.raises(SystemExit):
        main(["audit-verify", str(tmp_path / "missing.jsonl")])
    assert "cannot read" in capsys.readouterr().err


def pruned_export(entries: list[AuditLogEntry], pruned: int) -> list[str]:
    """What the server exports after retention removed the first [pruned]."""

    start = advance(ChainStart(), entries[:pruned])
    return list(chain_lines(entries[pruned:], until=NOW + timedelta(hours=2), start=start))


def test_an_older_export_still_verifies_after_a_prune() -> None:
    # AUD-009: pruning made legitimate retention look like tampering.
    events = [entry(minute) for minute in range(10)]
    older = export(events[:6])

    assert verify_extends(older, pruned_export(events, 2)).count == 8
    assert verify_extends(older, pruned_export(events, 6)).count == 4
    assert verify_extends(pruned_export(events[:6], 2), pruned_export(events, 4)).count == 6


def test_deleting_an_unpruned_event_still_breaks_the_chain() -> None:
    events = [entry(minute) for minute in range(10)]
    older = export(events[:6])
    tampered = events[:4] + events[5:]

    with pytest.raises(AuditChainError):
        verify_extends(older, pruned_export(tampered, 2))


def test_a_forged_checkpoint_does_not_verify() -> None:
    events = [entry(minute) for minute in range(10)]
    older = export(events[:6])
    forged = list(chain_lines(events[2:], until=NOW, start=ChainStart(head="f" * 64, count=2)))

    with pytest.raises(AuditChainError):
        verify_extends(older, forged)


def test_an_older_export_wholly_before_the_checkpoint_is_reported() -> None:
    events = [entry(minute) for minute in range(10)]

    with pytest.raises(AuditChainError, match="past every event"):
        verify_extends(export(events[:3]), pruned_export(events, 6))


def test_a_checkpoint_line_after_events_is_refused() -> None:
    lines = export([entry(0)])
    lines.insert(
        1, json.dumps({"format": "nebula-audit-chain/1", "checkpoint": GENESIS, "skipped": 1})
    )

    with pytest.raises(AuditChainError, match="checkpoint"):
        verify(lines)
