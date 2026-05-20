"""Alert delivery: console, file, or generic JSON webhook (Telegram/Slack/Pushover).

Webhook payload shape:
    POST <webhook_url>
    Content-Type: application/json
    {"title": "...", "body": "...", "ts": "<iso8601>"}

For Telegram, point webhook_url at https://api.telegram.org/bot<TOKEN>/sendMessage
and the body will be rendered as `{"chat_id": ..., "text": ...}` if you wrap
it with the helper in tg_format(); for Pushover/Slack use their native webhook.
"""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional


class Alerter:
    def __init__(
        self,
        channel: str = "console",
        webhook_url: Optional[str] = None,
        log_path: Optional[Path] = None,
    ):
        self.channel = channel
        self.webhook_url = webhook_url
        self.log_path = log_path

    def send(self, title: str, body: str) -> None:
        stamp = datetime.now().isoformat(timespec="seconds")
        msg = f"[{stamp}] {title}\n{body}"

        if self.channel == "console":
            print(msg)
            return

        if self.channel == "file":
            if not self.log_path:
                print(msg)
                return
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            with self.log_path.open("a") as f:
                f.write(msg + "\n---\n")
            return

        if self.channel == "webhook":
            if not self.webhook_url:
                print(msg)
                return
            payload = json.dumps({"title": title, "body": body, "ts": stamp}).encode()
            req = urllib.request.Request(
                self.webhook_url, data=payload, headers={"Content-Type": "application/json"}
            )
            try:
                urllib.request.urlopen(req, timeout=5).read()
            except (urllib.error.URLError, TimeoutError) as e:
                print(f"alert webhook failed: {e}\n{msg}")
            return

        print(msg)
