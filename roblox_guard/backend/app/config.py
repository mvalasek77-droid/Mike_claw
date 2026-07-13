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

    # Bearer token the iOS app must send on every request. Empty disables
    # auth (local development only) — production MUST set RG_API_TOKEN.
    api_token: str = os.environ.get("RG_API_TOKEN", "")

    # Directory for the persistent rotating bug/error log. Empty disables the
    # file handler (console-only, e.g. in tests).
    log_dir: str = os.environ.get("RG_LOG_DIR", "")

    # Where customer-submitted bug reports (and backend error alerts) get
    # emailed, if SMTP is configured. Every report is always stored in the
    # bug_reports table regardless of whether SMTP is set up.
    support_email: str = os.environ.get("RG_SUPPORT_EMAIL", "mvalasek@gmail.com")
    smtp_host: str = os.environ.get("RG_SMTP_HOST", "")
    smtp_port: int = _int("RG_SMTP_PORT", 587)
    smtp_user: str = os.environ.get("RG_SMTP_USER", "")
    smtp_password: str = os.environ.get("RG_SMTP_PASSWORD", "")
    smtp_from: str = os.environ.get("RG_SMTP_FROM", "")
    smtp_use_tls: bool = os.environ.get("RG_SMTP_USE_TLS", "1") not in ("0", "false", "False")

    # Push notifications (APNs, token-based auth). Unconfigured = no-op, same
    # pattern as SMTP above. RG_APNS_KEY_P8 carries the .p8 key content
    # directly for hosts with no persistent filesystem; RG_APNS_KEY_PATH is
    # an alternative for hosts that can mount a secret file. Key ID and Team
    # ID come from the Keys section of your Apple Developer account.
    apns_key_p8: str = os.environ.get("RG_APNS_KEY_P8", "")
    apns_key_path: str = os.environ.get("RG_APNS_KEY_PATH", "")
    apns_key_id: str = os.environ.get("RG_APNS_KEY_ID", "")
    apns_team_id: str = os.environ.get("RG_APNS_TEAM_ID", "")
    apns_bundle_id: str = os.environ.get("RG_APNS_BUNDLE_ID", "com.mikeclaw.robloxguard")
    apns_use_sandbox: bool = os.environ.get("RG_APNS_SANDBOX", "0") in ("1", "true", "True")

    extra: dict = field(default_factory=dict)


settings = Settings()
