"""Send one test alert through the configured channel, then exit.

Usage:
    export TRADING_ALERT_CHANNEL=telegram
    export TRADING_TELEGRAM_TOKEN=123456:ABCDEF...
    export TRADING_TELEGRAM_CHAT_ID=123456789
    python -m trading.alert_test
"""
from __future__ import annotations

from .config import CFG
from .execution.alerts import Alerter


def main() -> None:
    alerter = Alerter(
        channel=CFG.alert_channel,
        webhook_url=CFG.alert_webhook_url,
        log_path=CFG.journal_dir / "alerts.log",
        telegram_bot_token=CFG.telegram_bot_token,
        telegram_chat_id=CFG.telegram_chat_id,
        pushover_token=CFG.pushover_token,
        pushover_user=CFG.pushover_user,
    )
    print(f"channel={CFG.alert_channel}")
    alerter.send(
        "Oil bot test alert",
        "If you see this, alerts are wired up correctly.\n"
        f"Account: ${CFG.account_size_cad:.0f}\n"
        f"Universe: {CFG.longs_ticker} / {CFG.shorts_ticker}",
    )
    print("sent (check the channel)")


if __name__ == "__main__":
    main()
