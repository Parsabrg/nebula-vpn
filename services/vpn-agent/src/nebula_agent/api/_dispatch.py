"""Shared idempotency-ledgered dispatch, used by both api/v1.py (WireGuard)
and api/v1_xray.py (Xray) so a retried request with the same idempotency_key
replays the stored response instead of re-running the driver, regardless of
which protocol's router it hit.
"""

import asyncio
import hashlib
import weakref
from collections.abc import Awaitable, Callable
from uuid import UUID

from fastapi import HTTPException, Request, status
from pydantic import BaseModel

from nebula_agent.ledger import OperationLedger

MAX_OPERATION_BODY_BYTES = 16 * 1024


async def enforce_body_size_limit(request: Request) -> None:
    """Defense in depth beyond the typed models themselves, which already
    have no unbounded free-form fields."""

    content_length = request.headers.get("content-length")
    if content_length is not None and not content_length.isdigit():
        # A 400, not a 500 from int() (AUD-026).
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="bad content-length")
    if content_length is not None and int(content_length) > MAX_OPERATION_BODY_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail="request body too large"
        )


def get_ledger(request: Request) -> OperationLedger:
    ledger: OperationLedger = request.app.state.ledger
    return ledger


# One lock per key while a request with it runs: two concurrent requests with
# the same key would otherwise both miss the ledger and both apply. The agent
# is a single process (one uvicorn server), so an in-process lock is enough.
_key_locks: weakref.WeakValueDictionary[UUID, asyncio.Lock] = weakref.WeakValueDictionary()


def request_fingerprint(payload: BaseModel) -> str:
    """The request without its key: a key replayed with any other content is
    a different operation."""

    body = payload.model_dump_json(exclude={"idempotency_key"})
    return hashlib.sha256(body.encode()).hexdigest()


async def dispatch_ledgered[ResponseT: BaseModel](
    *,
    ledger: OperationLedger,
    idempotency_key: UUID,
    operation_kind: str,
    target_id: UUID,
    payload: BaseModel,
    response_model: type[ResponseT],
    run: Callable[[], Awaitable[ResponseT]],
) -> ResponseT:
    fingerprint = request_fingerprint(payload)
    lock = _key_locks.get(idempotency_key)
    if lock is None:
        lock = asyncio.Lock()
        _key_locks[idempotency_key] = lock
    async with lock:
        cached = ledger.lookup(idempotency_key)
        if cached is not None:
            if (
                cached.operation_kind != operation_kind
                or cached.target_id != str(target_id)
                # Entries written before fingerprints have none to compare.
                or (cached.request_fingerprint and cached.request_fingerprint != fingerprint)
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="idempotency_key was already used for a different operation",
                )
            return response_model.model_validate_json(cached.response_json)
        response = await run()
        ledger.record(
            idempotency_key=idempotency_key,
            operation_kind=operation_kind,
            target_id=target_id,
            request_fingerprint=fingerprint,
            applied_generation=response.applied_generation,  # type: ignore[attr-defined]
            response_json=response.model_dump_json(),
        )
        return response
