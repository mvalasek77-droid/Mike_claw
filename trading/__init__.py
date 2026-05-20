"""Oil-ETF (HOU.TO / HOD.TO) signal-only trading bot.

Honest constraints baked in by design:
    - Mogo has no trading API. The bot only emits signals; user clicks BUY/SELL in Mogo.
    - HOU/HOD trade only during TSX hours (09:30-16:00 ET, Mon-Fri).
    - Leveraged 2x daily-reset ETFs decay in chop; bot enforces max hold + regime gate.

See docs/trading_bot.md for strategy attribution and run instructions.
"""
