"""Lightweight caching utilities for expensive database queries.

Avoids adding external dependencies (flask-caching) by using Python's
built-in functools.lru_cache with a TTL wrapper.
"""
import time
from functools import wraps
from sqlalchemy.orm import make_transient


def ttl_cache(seconds=300):
    """Decorator that adds TTL expiration to functools.lru_cache.

    Args:
        seconds: Cache lifetime in seconds (default 5 minutes).

    Returns:
        Decorated function with caching + TTL.
    """

    def decorator(func):
        # Use a mutable container for the expiry timestamp
        _expiry = [0.0]
        _cached_result = [None]

        @wraps(func)
        def wrapper(*args, **kwargs):
            now = time.time()
            if now >= _expiry[0] or _cached_result[0] is None:
                _cached_result[0] = func(*args, **kwargs)
                _expiry[0] = now + seconds
            return _cached_result[0]

        def cache_clear():
            _expiry[0] = 0.0
            _cached_result[0] = None

        wrapper.cache_clear = cache_clear
        return wrapper

    return decorator


# ── Cached athlete record ────────────────────────────────────────────
# The athlete table has exactly 1 row and is queried 13+ times per
# page load across different callbacks.  Cache it for 60 seconds.

@ttl_cache(seconds=60)
def get_athlete():
    """Return the athlete record (athlete_id=1), cached for 60s.

    The ORM object is expunged from the session so it remains usable
    after session.remove() is called in any callback.
    """
    from .app import app
    from .api.sqlalchemy_declarative import athlete

    obj = app.session.query(athlete).filter(athlete.athlete_id == 1).first()
    if obj is not None:
        # Detach from session so cached object survives session.remove()
        app.session.expunge(obj)
        make_transient(obj)
    app.session.remove()
    return obj

