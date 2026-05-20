# Oil ETF Signal Bot (HOU.TO / HOD.TO)

A 30-minute, signal-only trading bot for the leveraged Canadian crude
ETFs. The bot computes signals around the clock, but only emits
**hard buy/sell decisions** during TSX hours and only when the trade
clears a small-account economic-viability gate. You tap the trade in
Mogo manually — Mogo has no developer API.

## Why signal-only

- **Mogo has no public trading API.** Any automated order-entry would be ToS-violating scraping that breaks on every release. We do not do that here.
- **HOU/HOD only trade 09:30–16:00 ET Mon–Fri** on the TSX. No 24/7 trading exists for these instruments.
- **Leveraged 2x daily-reset ETFs decay in chop.** The bot enforces a max hold of 1 day and refuses to trade in chop regime.
- **Small account ($180 default).** The viability gate refuses trades whose expected 30-minute return doesn't beat 0.5% round-trip slippage by a margin.

## Hard decision output

Every 30 minutes the bot prints (or webhooks) one of:

- `BUY HOU.TO  alpha=+X.XX%  beta=+Y.YY` — model expects crude up; click BUY HOU in Mogo for the suggested share count.
- `BUY HOD.TO  alpha=+X.XX%  beta=-Y.YY` — model expects crude down; click BUY HOD.
- `SELL <ticker>` — close the current position.
- `HOLD <ticker>` — keep the position; no new action.
- `STAY OUT` — no edge or viability fails; sit on hands.
- `WAIT FOR OPEN` — signal is valid but TSX is closed.

`alpha` is the expected 30-minute return on the ETF (signed). `beta` is the rolling regression coefficient of the ETF's log-returns on WTI (CL=F) log-returns over the last 100 30-min bars; HOU should run near +2, HOD near −2.

## Strategy ensemble

Six members, each with attribution:

| # | Strategy | Source | Regime | Notes |
|---|----------|--------|--------|-------|
| 1 | AQR Time-Series Momentum | Moskowitz, Ooi, Pedersen, *J. Financial Economics* 104 (2012) | All | 12-month past-return sign as slow regime confirmation |
| 2 | Donchian / Turtle Breakout | Dennis & Eckhardt (1983); Curtis Faith, *Way of the Turtle* (2007) | Trend | 20-day entry, 10-day exit, ATR stops |
| 3 | Trendline Mean-Reversion | Edwards & Magee, *Technical Analysis of Stock Trends* | Chop only | Wick-pivot anchored support/resistance, fade extremes |
| 4 | Trendline Breakout | Edwards & Magee | Trend only | Close > line + 0.5·ATR → enter break direction |
| 5 | Connors RSI(2) | Connors & Alvarez, *Short Term Trading Strategies That Work* (2009) | All | RSI(2) < 10 buy, > 90 fade — empirical short-horizon reversion |
| 6 | Session VWAP + EMA bias | Day-trader heuristic | All | Above/below VWAP with 50-EMA slope as confirmation |

**Weights:** equal at start. The learning module reads the journal and
shifts weights toward inverse-variance (Bridgewater risk-parity flavour)
every 20 cycles. Noisy strategies shrink automatically.

**Goldman Sachs note:** Goldman's prop strategies are not public. The closest
publicly-documented Goldman strategy in commodities is the *Goldman Roll*
— front-running the rolling of GSCI front-month contracts, documented
academically and largely arbed out post-2012. It is not implementable in
HOU/HOD (it requires futures), so we do not include it. The risk-parity
sizing, vol-targeting, ATR stops, and ensemble blending here are the
institutional habits that *are* applicable.

## Trendline construction

Pivot detection follows the classical "long wick" rule: a bar is a swing
high if its `high` exceeds the `high` of `left` bars before and `right`
bars after, with the same for swing lows. This matches what investing.com
draws by default. Trendlines are linear regressions through the most
recent 8 pivots, requiring at least 3. Break detection requires the close
to cross the line by 0.5·ATR — the buffer kills micro-flickers.

## Risk gates (in evaluation order)

1. **EIA blackout** — Wednesdays 10:30 ET ± 20 minutes (US crude inventory print).
2. **Daily loss cap** — 5% of account ($9 on $180). No new trades for the day once tripped.
3. **Minimum confidence** — ensemble must net ≥ 0.30 conviction or STAY OUT.
4. **Viability gate** — expected 30-min ETF move ≥ 0.8%; expected $ profit after 0.5% slippage ≥ $0.50; reward / 1σ ≥ 0.25.
5. **Max hold = 1 day** — decay-aware hard exit; flips on counter-signal; stops on ATR.

## Setup

```bash
pip install -r requirements.txt
python -m trading.bot          # live 30-min loop, console alerts
python -m trading.backtest --years 2
```

### Push alerts to your phone

Each channel uses its native API shape — no relay needed for Telegram, Slack, Discord, or Pushover. Configure with env vars (recommended, keeps secrets out of source) or by editing `trading/config.py`.

**Telegram (recommended for phone alerts):**

1. Open Telegram, message **@BotFather**, `/newbot`, follow prompts → you get a token like `123456:ABC-DEF...`.
2. Message **@userinfobot** to get your numeric chat id.
3. Send your new bot any message first (otherwise it can't DM you).
4. Configure and test:

```bash
export TRADING_ALERT_CHANNEL=telegram
export TRADING_TELEGRAM_TOKEN="123456:ABC-DEF..."
export TRADING_TELEGRAM_CHAT_ID="123456789"
python -m trading.alert_test            # one test message to your phone
python -m trading.bot                   # live 30-min alerts
```

**Slack / Discord:**

```bash
export TRADING_ALERT_CHANNEL=slack       # or discord
export TRADING_ALERT_WEBHOOK_URL="https://hooks.slack.com/services/..."
python -m trading.alert_test
```

**Pushover:**

```bash
export TRADING_ALERT_CHANNEL=pushover
export TRADING_PUSHOVER_TOKEN=...
export TRADING_PUSHOVER_USER=...
python -m trading.alert_test
```

**Generic webhook** (your own relay receiving `{title, body, ts}`):

```bash
export TRADING_ALERT_CHANNEL=webhook
export TRADING_ALERT_WEBHOOK_URL=https://yourserver.example/hook
```

## What this bot will *not* do

- Place orders on Mogo. (No API. You tap them.)
- Trade 24/7. (TSX hours only; monitor 24/7.)
- Use scraped investing.com candles. (yfinance is the data source.)
- Promise alpha. The alpha forecast is a model estimate using the ensemble's signed conviction and the underlying's recent vol — it is *not* a guarantee.
- Hold overnight. (Decay risk on 2x daily-reset ETFs.)

## Tuning checklist when the journal has 50+ outcomes

- Check `learning.evaluator.stats` per strategy. Drop any with `n>20` and `sharpe<0`.
- Examine `regime_hit_rate` for `trend` vs `chop`. If chop hit rate < 50%, raise `min_signal_confidence` for mean-revert members.
- If max-hold exits dominate stop exits, reconsider `atr_stop_mult` upward.
- If beta R² < 0.5 most days, the underlying choice may be wrong — try BNO or front-month BZ=F as the regressor.

## Honest assessment

The retail and academic literature is consistent: for a $100–500 account
on leveraged daily-reset ETFs with 0.5–1% bid-ask spreads, the realistic
edge is small and entirely intraday. The strategies most likely to
survive in this regime are **(a) Donchian breakout on the underlying**,
**(b) Connors RSI(2) reversion** with ≤1-day hold, and **(c) hard
ATR-based stops**. Everything else here is structural support around
those two ideas. Paper-trade for 4–8 weeks before you risk real
dollars — the equity curve in `storage/journal/signals.jsonl` is the
ground truth.
