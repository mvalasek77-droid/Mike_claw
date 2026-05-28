#!/bin/bash
cd /Users/clawcl/code/Mike_claw
source /Users/clawcl/code/Mike_claw/.venv311/bin/activate
export TRADING_ALERT_CHANNEL=telegram
export TRADING_TELEGRAM_TOKEN="8784772860:AAGIoUVOuDCNcGGWceZE8W43fgOpPn_OoL4"
export TRADING_TELEGRAM_CHAT_ID="8355819128"
exec python -m trading.bot

