"""Persistent, bounded logging for every `roblox_guard.*` logger.

Without this, module-level `log.exception(...)` calls (already scattered
through monitor.py, evidence.py, etc.) only reach whatever the process's
stdout happens to be piped to — fine for local dev, useless after a crash on
a real server. This adds a rotating file handler so operational errors
survive process restarts and are inspectable after the fact, independent of
the customer-facing bug_reports table.
"""

import logging
import logging.handlers
import os


def configure_logging(log_dir: str) -> None:
    root = logging.getLogger("roblox_guard")
    if root.handlers:
        return  # already configured (e.g. re-entrant app factory in tests)
    root.setLevel(logging.INFO)

    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s: %(message)s", datefmt="%Y-%m-%dT%H:%M:%S%z"
    )

    console = logging.StreamHandler()
    console.setFormatter(formatter)
    root.addHandler(console)

    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
        file_handler = logging.handlers.RotatingFileHandler(
            os.path.join(log_dir, "app.log"),
            maxBytes=5 * 1024 * 1024,
            backupCount=5,
        )
        file_handler.setFormatter(formatter)
        root.addHandler(file_handler)
