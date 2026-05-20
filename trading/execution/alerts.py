"""Alert delivery: console, file, or chat-app adapter (Telegram / Slack / Discord / Pushover / generic webhook).

Each channel uses its native payload shape so it works without a relay:

    console      Stdout. Default.
    file         Append to a log file.
    telegram     POST https://api.telegram.org/bot<TOKEN>/sendMessage
                 body: {"chat_id": <id>, "text": <msg>, "parse_mode": "HTML"}
                 Requires: telegram_bot_token, telegram_chat_id.
    slack        POST <webhook_url>           body: {"text": <msg>}
    discord      POST <webhook_url>           body: {"content": <msg>}
    pushover     POST https://api.pushover.net/1/messages.json
                 body: {token, user, title, message}
                 Requires: pushover_token, pushover_user.
    webhook      POST <webhook_url>           body: {title, body, ts}  -- for a relay you control.

Telegram chat_id: message @userinfobot from your own account to see it,
or for groups add the bot then call /start and inspect updates at
https://api.telegram.org/bot<TOKEN>/getUpdates.
"""
from __future__ import annotations

import json
import urllib.error
import urllib.parse
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
        telegram_bot_token: Optional[str] = None,
        telegram_chat_id: Optional[str] = None,
        pushover_token: Optional[str] = None,
        pushover_user: Optional[str] = None,
    ):
        self.channel = channel
        self.webhook_url = webhook_url
        self.log_path = log_path
        self.telegram_bot_token = telegram_bot_token
        self.telegram_chat_id = telegram_chat_id
        self.pushover_token = pushover_token
        self.pushover_user = pushover_user

    def send(self, title: str, body: str) -> None:
        stamp = datetime.now().isoformat(timespec="seconds")
        msg = f"[{stamp}] {title}\n{body}"

        try:
            if self.channel == "console":
                print(msg)
            elif self.channel == "file":
                self._send_file(msg)
            elif self.channel == "telegram":
                self._send_telegram(title, body)
            elif self.channel == "slack":
                self._post_json(self.webhook_url, {"text": msg})
            elif self.channel == "discord":
                self._post_json(self.webhook_url, {"content": msg[:1900]})
            elif self.channel == "pushover":
                self._send_pushover(title, body)
            elif self.channel == "webhook":
                self._post_json(self.webhook_url, {"title": title, "body": body, "ts": stamp})
            else:
                print(msg)
        except Exception as e:
            print(f"alert {self.channel} failed: {e}\n{msg}")

    def _send_file(self, msg: str) -> None:
        if not self.log_path:
            print(msg); return
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        with self.log_path.open("a") as f:
            f.write(msg + "\n---\n")

    def _send_telegram(self, title: str, body: str) -> None:
        if not (self.telegram_bot_token and self.telegram_chat_id):
            print(f"[telegram not configured] {title}\n{body}"); return
        url = f"https://api.telegram.org/bot{self.telegram_bot_token}/sendMessage"
        text = f"<b>{_html_escape(title)}</b>\n{_html_escape(body)}"
        if len(text) > 4000:
            text = text[:3997] + "..."
        payload = {
            "chat_id": self.telegram_chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        self._post_json(url, payload)

    def _send_pushover(self, title: str, body: str) -> None:
        if not (self.pushover_token and self.pushover_user):
            print(f"[pushover not configured] {title}\n{body}"); return
        data = urllib.parse.urlencode({
            "token": self.pushover_token,
            "user": self.pushover_user,
            "title": title[:250],
            "message": body[:1024],
        }).encode()
        req = urllib.request.Request(
            "https://api.pushover.net/1/messages.json",
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        urllib.request.urlopen(req, timeout=8).read()

    @staticmethod
    def _post_json(url: Optional[str], payload: dict) -> None:
        if not url:
            print(f"[no webhook url] {payload}"); return
        body = json.dumps(payload).encode()
        req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=8).read()


def _html_escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
