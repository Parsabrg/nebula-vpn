"""At most one audit row per rate-limit bucket and window.

A rate-limited request used to add an audit row each time, so anyone could
grow the audit table without bound by repeating a refused request (audit
AUD-017). The first refusal in a window is recorded; the rest are what the
rate limit is for.
"""

import time

from nebula_api.auth.redis_state import RateBucket

# ponytail: per service object in this process; one API process by design.
_MAX_KEYS = 10_000


def first_denial(
    seen: dict[str, float], buckets: tuple[RateBucket, ...], window_seconds: int
) -> bool:
    """Whether this is the first refusal for [buckets] in the window; records it."""

    now = time.monotonic()
    key = "|".join(f"{bucket.namespace}:{bucket.subject}" for bucket in buckets)
    if seen.get(key, 0.0) > now:
        return False
    if len(seen) >= _MAX_KEYS:
        for stale in [name for name, until in seen.items() if until <= now]:
            del seen[stale]
        if len(seen) >= _MAX_KEYS:
            seen.clear()
    seen[key] = now + window_seconds
    return True
