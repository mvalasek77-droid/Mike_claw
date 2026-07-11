"""Runtime configuration for the RobloxGuard backend.

Everything is overridable via environment variables so the same build runs
locally, in CI, and behind a real deployment without code changes.
"""

import os
from dataclasses import dataclass, field


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


@dataclass
class Settings:
    db_path: str = os.environ.get("RG_DB_PATH", "roblox_guard.db")

    # How often the background monitor re-polls each linked child account.
    poll_interval_seconds: int = _int("RG_POLL_INTERVAL", 15 * 60)

    # Minimum delay between consecutive Roblox API calls (politeness / rate limit).
    request_spacing_seconds: float = float(os.environ.get("RG_REQUEST_SPACING", "0.5"))

    # A friend account created more than this many years ago is old enough to
    # be surfaced as an "established account" fact when other signals fire.
    established_account_years: float = float(os.environ.get("RG_ESTABLISHED_YEARS", "5"))

    # Friend-count threshold above which an account is surfaced as a
    # "very large network" fact (Roblox caps friends at 1000).
    mass_friender_threshold: int = _int("RG_MASS_FRIENDER_THRESHOLD", 700)

    # Number of new friends within the rapid-friending window that triggers a signal.
    rapid_friend_count: int = _int("RG_RAPID_FRIEND_COUNT", 5)
    rapid_friend_window_hours: int = _int("RG_RAPID_FRIEND_WINDOW_HOURS", 24)

    # Quiet hours (local time, 24h clock). Presence observed inside this window
    # raises a late-night activity signal. start > end means the window wraps
    # past midnight (e.g. 22 -> 6).
    quiet_hours_start: int = _int("RG_QUIET_START", 22)
    quiet_hours_end: int = _int("RG_QUIET_END", 6)

    # Path to the curated experience watchlist (JSON). Ships as a template;
    # operators maintain their own entries.
    watchlist_path: str = os.environ.get(
        "RG_WATCHLIST_PATH",
        os.path.join(os.path.dirname(__file__), "..", "data", "experience_watchlist.json"),
    )

    extra: dict = field(default_factory=dict)


settings = Settings()
