#!/bin/bash
# Trading bot launcher with Telegram alerts
export TRADING_ALERT_CHANNEL=telegram
export TRADING_TELEGRAM_TOKEN="8784772860:AAGIoUVOuDCNcGGWceZE8W43fgOpPn_OoL4"
export TRADING_TELEGRAM_CHAT_ID="8355819128"

cd /Users/clawcl/code/Mike_claw
source .venv311/bin/activate

echo "$(date): Starting trading bot..." >> trading/storage/journal/bot.log
python -m trading.bot 2>&1 | tee -a trading/storage/journal/bot.log