from nebula_api.auth.denial_audit import first_denial
from nebula_api.auth.redis_state import RateBucket


def test_first_denial_once_per_window_per_bucket() -> None:
    seen: dict[str, float] = {}
    a = (RateBucket("login", "1.2.3.0/24"),)
    b = (RateBucket("login", "5.6.7.0/24"),)
    assert first_denial(seen, a, 60)
    assert not first_denial(seen, a, 60)
    assert first_denial(seen, b, 60)
    seen.clear()
    assert first_denial(seen, a, 0)
    assert first_denial(seen, a, 0)  # expired at once
