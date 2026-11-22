import asyncio
import json
from pathlib import Path, PurePosixPath
from uuid import uuid4

import pytest
from pydantic import BaseModel

from nebula_agent.api._dispatch import dispatch_ledgered
from nebula_agent.ledger import OperationLedger


class _Payload(BaseModel):
    idempotency_key: str
    value: int


class _Response(BaseModel):
    applied_generation: int


@pytest.mark.anyio
async def test_concurrent_requests_with_one_key_apply_once(tmp_path: Path) -> None:
    ledger = OperationLedger(PurePosixPath(str(tmp_path / "ledger.jsonl")), 100)
    key, target = uuid4(), uuid4()
    payload = _Payload(idempotency_key=str(key), value=1)
    runs = 0

    async def run() -> _Response:
        nonlocal runs
        runs += 1
        await asyncio.sleep(0.05)
        return _Response(applied_generation=runs)

    async def call() -> _Response:
        return await dispatch_ledgered(
            ledger=ledger,
            idempotency_key=key,
            operation_kind="provision_device",
            target_id=target,
            payload=payload,
            response_model=_Response,
            run=run,
        )

    results = await asyncio.gather(call(), call(), call())

    assert runs == 1
    assert {result.applied_generation for result in results} == {1}


def test_a_ledger_written_before_fingerprints_still_loads(tmp_path: Path) -> None:
    path = tmp_path / "ledger.jsonl"
    key = uuid4()
    old_entry = {
        "idempotency_key": str(key),
        "operation_kind": "k",
        "target_id": "t",
        "applied_generation": 0,
        "response_json": "{}",
    }
    path.write_text(json.dumps(old_entry) + "\n")
    ledger = OperationLedger(PurePosixPath(str(path)), 100)

    entry = ledger.lookup(key)
    assert entry is not None
    assert entry.request_fingerprint == ""
