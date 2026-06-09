#!/usr/bin/env python3
"""
W-M Binary Signal Engine
=========================
Always gives you a direction. No WAIT, no maybe.

Rules (from backtested edge):
1. M-pattern -> SHORT is king (93% WR). Always prefer M_SELL.
2. M_BUY (buy M-bottom bounce) is queen (87% WR).
3. W-pattern -> AVOID trading. W_BUY 11%, W_SELL 4%.
4. If only W visible -> use regime as tiebreaker:
   - DOWN regime -> SHORT (the W is a trap, it'll make a lower low)
   - UP regime -> LONG (the W bottom will hold)
5. RSI >60 confirms. RSI <40 penalizes.
6. Confirmation zone (60%+ through pattern) = strongest.
7. Early zone (<15%) = new pattern starting = trade it.
8. Consolidation zone (25-60%) = 0% WR -> DO NOT enter here,
   but we still report the direction because you need one.

Output format (one ticker, one line, always a direction):
  TICKER  $XX.XX  LONG  Entry $XX.XX  Target $XX.XX  Stop $XX.XX  [Grade] WR%
  or
  TICKER  $XX.XX  SHORT  Entry $XX.XX  Target $XX.XX  Stop $XX.XX  [Grade] WR%
"""

import sys
import json
import numpy as np
import warnings
from pathlib import Path
from datetime import datetime
from pytz import timezone

warnings.filterwarnings("ignore")

STORAGE = Path(__file__).parent / "storage"
ET = timezone('US/Eastern')

# Import the tactical scanner
import wm_tactical as wt

# Backtested Win Rates (1935 trades, 2026-06-03)
BASE_WR = {
    'M_SELL':    0.87,   # Queen - sell M-top reversal
    'M_BUY':     0.93,   # King  - buy M-bottom bounce
    'W_BUY':     0.11,   # Avoid
    'W_SELL':    0.04,   # Avoid
    'DOWN_SELL': 0.83,   # Regime-confirmed sell
    'DOWN_BUY':  0.17,   # Against regime
    'UP_BUY':    0.70,   # Regime-confirmed buy (estimated)
    'UP_SELL':   0.30,   # Against regime
}

# Regime adjustments (v6 — DOWN+BUY much harsher after 6/5 misses)
REGIME_ADJ_BINARY = {
    'DOWN':    {'BUY': -0.20, 'SELL': 0.05},   # DOWN+BUY was 30% WR, cost us WTI
    'UP':      {'BUY':  0.05, 'SELL': -0.05},
    'SIDEWAYS': {'BUY': 0,    'SELL': 0},
}


def binary_signal(ticker, send_alerts=True):
    """Always return LONG or SHORT with entry/target/stop."""
    sym = wt.TICKERS.get(ticker, {}).get("symbol")
    if not sym:
        return None

    # Fetch data
    data = wt.fetch_multi(sym)
    if '1d' not in data or len(data['1d']['close']) < 20:
        return None

    price = float(data['1d']['close'][-1])
    regime = wt.detect_regime(data['1d']['close'])
    atr = wt.compute_atr(data['1d']['high'], data['1d']['low'], data['1d']['close'])

    # v6: Intraday regime override — if stock is crashing -5%+ today,
    # force DOWN regardless of what the SMA says (prevent buying in freefall)
    if '15m' in data and len(data['15m']['close']) > 0:
        intraday_open = float(data['15m']['close'][0])
        daily_chg_pct = ((price - intraday_open) / intraday_open) * 100 if intraday_open > 0 else 0
        if daily_chg_pct < -5 and regime != 'DOWN':
            regime = 'DOWN'  # intraday crash overrides SMA regime

    # Collect all signals from tactical scanner
    signals = wt.tactical_signal(
        data.get('15m'), data.get('1h'), data.get('1d'),
        price, regime, atr
    )

    # Determine pattern state (1d/2h is the anchor)
    pattern_type = 'NONE'
    pattern_pct = 50
    pattern_floor = price * 0.95
    pattern_ceil = price * 1.05
    pattern_conf = 0
    pattern_action = 'WAIT'
    source = ''

    # Priority: macro override > 2h (1d) > 1h > 30m
    if 'macro' in signals:
        ma = signals['macro']
        if ma['type'] == 'MACRO_M_OVERRIDE':
            pattern_type = 'M'
            pattern_pct = ma['pct']
            pattern_floor = ma['floor']
            pattern_ceil = ma['ceiling']
            pattern_conf = min(1.0, ma['strength'] + 0.3)
            pattern_action = 'SELL'
            source = 'macro_M'
        elif ma['type'] == 'MACRO_W_OVERRIDE':
            pattern_type = 'W'
            pattern_pct = ma['pct']
            pattern_floor = ma['floor']
            pattern_ceil = ma['ceiling']
            pattern_conf = min(1.0, ma['strength'] + 0.3)
            # W override says BUY but W_BUY is only 9.4% WR
            # Check shorter timeframe signals for sell pressure (crash detection)
            shorter_sell = False
            for tf in ['1h', '30m']:
                if tf in signals and signals[tf].get('action') == 'SELL':
                    shorter_sell = True
                    break
            # Also check if daily change is deeply negative
            daily_sell = ma.get('daily_chg_pct', 0) < -5
            if shorter_sell or daily_sell:
                pattern_action = 'WAIT'   # sell signals on shorter TF = trap
                pattern_type = 'NONE'     # cancel W pattern, let detectors win
            else:
                pattern_action = 'BUY'
            source = 'macro_W'

    if pattern_type == 'NONE' and '2h' in signals:
        s = signals['2h']
        pattern_type = s['type']
        pattern_pct = s['pct']
        pattern_floor = s.get('floor', pattern_floor)
        pattern_ceil = s.get('ceil', pattern_ceil)
        pattern_conf = s.get('confidence', 0.5)
        pattern_action = s['action']
        source = '2h'

    if pattern_type == 'NONE' and '1h' in signals:
        s = signals['1h']
        if s['type'] in ('W', 'M'):
            pattern_type = s['type']
            pattern_pct = s['pct']
            pattern_conf = s.get('confidence', 0.5)
            pattern_action = s['action']
            source = '1h'

    if pattern_type == 'NONE' and '30m' in signals:
        s = signals['30m']
        if s['type'] in ('W', 'M'):
            pattern_type = s['type']
            pattern_pct = s['pct']
            pattern_conf = s.get('confidence', 0.5)
            pattern_action = s['action']
            source = '30m'

    # Move detectors
    spike_sell = 'spike' in signals and signals['spike']['action'] == 'SELL'
    dip_buy = 'dip' in signals and signals['dip']['action'] == 'BUY'
    mom_sell = 'momentum' in signals and signals['momentum']['action'] == 'SELL'
    mom_buy = 'momentum' in signals and signals['momentum']['action'] == 'BUY'

    # ======================================================================
    # BINARY DECISION - always LONG or SHORT
    # ======================================================================
    direction = None
    win_rate = 0.5
    grade = 'C'
    notes = []
    key = ''

    if pattern_type == 'M':
        # M pattern: double top
        if pattern_pct >= 75:
            # Near M bottom = KING TRADE: buy the bounce
            direction = 'LONG'
            key = 'M_BUY'
            win_rate = BASE_WR['M_BUY']
            # BUT: M-bounce in DOWN regime is dangerous (30% WR)
            # v6: CANCEL the trade entirely in DOWN regime
            if regime == 'DOWN':
                direction = 'SHORT'     # flip to SHORT — respect the regime
                key = 'M_SELL'
                win_rate = BASE_WR['M_SELL'] * 0.70   # moderate SHORT
                notes.append(f"M-bounce DOWN⚠️→FLIP SHORT")
            else:
                notes.append(f"M-bounce KING")
        elif pattern_pct >= 60:
            # Confirmation zone: M completing downward -> SHORT
            direction = 'SHORT'
            key = 'M_SELL'
            win_rate = BASE_WR['M_SELL']
            notes.append(f"M {pattern_pct:.0f}% confirm")
        elif pattern_pct <= 25:
            # Early: near M top -> SELL
            direction = 'SHORT'
            key = 'M_SELL'
            win_rate = BASE_WR['M_SELL'] * 0.85
            notes.append(f"M-top early {pattern_pct:.0f}%")
        else:
            # Mid-zone: still SHORT (it's an M), but low WR
            direction = 'SHORT'
            key = 'M_SELL'
            win_rate = BASE_WR['M_SELL'] * 0.5
            notes.append(f"M mid-zone caution")

    elif pattern_type == 'W':
        # W pattern: double bottom
        if pattern_pct >= 75:
            # Near W completion (top) -> W completed, take profit = SHORT
            direction = 'SHORT'
            key = 'W_SELL'
            win_rate = BASE_WR['W_SELL']
            notes.append(f"W completed (weak)")
        elif pattern_pct <= 25:
            # Near W bottom -> W_BUY (but 11% WR!)
            direction = 'LONG'
            key = 'W_BUY'
            win_rate = BASE_WR['W_BUY']
            notes.append(f"W-bottom (low WR)")
        else:
            # Mid-zone: use regime as tiebreaker
            if regime == 'DOWN':
                direction = 'SHORT'
                key = 'DOWN_SELL'
                win_rate = BASE_WR.get('DOWN_SELL', 0.5)
                notes.append(f"W+DOWN->SHORT")
            elif regime == 'UP':
                direction = 'LONG'
                key = 'UP_BUY'
                win_rate = BASE_WR.get('UP_BUY', 0.5)
                notes.append(f"W+UP->LONG")
            else:
                direction = 'LONG'  # W = bottom, default LONG
                win_rate = 0.3
                notes.append(f"W+SIDEWAYS")

    else:
        # No pattern detected - use regime
        if regime == 'DOWN':
            direction = 'SHORT'
            key = 'DOWN_SELL'
            win_rate = BASE_WR.get('DOWN_SELL', 0.5)
            notes.append(f"No pattern+DOWN")
        elif regime == 'UP':
            direction = 'LONG'
            key = 'UP_BUY'
            win_rate = BASE_WR.get('UP_BUY', 0.5)
            notes.append(f"No pattern+UP")
        else:
            direction = 'LONG'
            win_rate = 0.35
            notes.append(f"Default LONG")

    # Move detector overrides
    if spike_sell and direction != 'SHORT':
        direction = 'SHORT'
        win_rate = max(win_rate, 0.70)
        notes.append("spike-override->SHORT")
    elif spike_sell and direction == 'SHORT':
        win_rate = min(1.0, win_rate + 0.05)
        notes.append("spike-confirms")

    if dip_buy and direction != 'LONG':
        direction = 'LONG'
        win_rate = max(win_rate, 0.70)
        notes.append("dip-override->LONG")
    elif dip_buy and direction == 'LONG':
        win_rate = min(1.0, win_rate + 0.05)
        notes.append("dip-confirms")

    if mom_sell and direction == 'SHORT':
        win_rate = min(1.0, win_rate + 0.05)
        notes.append("mom-confirms")
    elif mom_sell and direction == 'LONG':
        win_rate = max(0.2, win_rate - 0.10)
        notes.append("mom-vs-position!")

    if mom_buy and direction == 'LONG':
        win_rate = min(1.0, win_rate + 0.05)
        notes.append("mom-confirms")
    elif mom_buy and direction == 'SHORT':
        win_rate = max(0.2, win_rate - 0.10)
        notes.append("mom-vs-position!")

    # RSI adjustments
    rsi = None
    for tf in ('2h', '1h', '30m'):
        if tf in signals and 'rsi' in signals[tf]:
            rsi = signals[tf]['rsi']
            break

    if rsi is not None:
        if rsi >= 70:
            if direction == 'LONG':
                win_rate = min(1.0, win_rate + 0.10)
                notes.append(f"RSI{rsi:.0f}++")
            else:
                win_rate = max(0.2, win_rate - 0.05)
                notes.append(f"RSI{rsi:.0f}-vs")
        elif rsi >= 60:
            if direction == 'LONG':
                win_rate = min(1.0, win_rate + 0.05)
                notes.append(f"RSI{rsi:.0f}+")
            else:
                win_rate = max(0.2, win_rate - 0.05)
                notes.append(f"RSI{rsi:.0f}-vs")
        elif rsi <= 30:
            # v6: Oversold depends on context
            if direction == 'SHORT' and regime == 'DOWN':
                win_rate = min(1.0, win_rate + 0.05)  # oversold in downtrend = momentum
                notes.append(f"RSI{rsi:.0f}+freefall")
            elif direction == 'LONG' and regime == 'DOWN':
                win_rate = max(0.05, win_rate - 0.30)  # oversold LONG in DOWN = trap
                notes.append(f"RSI{rsi:.0f}!!TRAP")
            else:
                win_rate = max(0.2, win_rate - 0.15)   # mild penalty in UP
                notes.append(f"RSI{rsi:.0f}!!")
        elif rsi < 40:
            if direction == 'LONG':
                win_rate = max(0.2, win_rate - 0.15)
            else:
                win_rate = max(0.2, win_rate - 0.10)
            notes.append(f"RSI{rsi:.0f}!")

    # Confidence adjustment
    if pattern_conf > 0.85 and pattern_type == 'M':
        win_rate = min(1.0, win_rate + 0.03)
        notes.append("conf+")

    # Regime adjustment (v6)
    regime_adj = REGIME_ADJ_BINARY.get(regime, {'BUY': 0, 'SELL': 0})
    action_key = 'BUY' if direction == 'LONG' else 'SELL'
    win_rate += regime_adj.get(action_key, 0)
    win_rate = max(0.05, min(0.98, win_rate))

    # Grade
    if win_rate >= 0.80:
        grade = 'A'
    elif win_rate >= 0.65:
        grade = 'B'
    elif win_rate >= 0.45:
        grade = 'C'
    else:
        grade = 'D'

    # W-pattern trades always D
    if pattern_type == 'W' and key in ('W_BUY', 'W_SELL'):
        grade = 'D'

    # ======================================================================
    # CALCULATE ENTRY / TARGET / STOP
    # ======================================================================
    entry = price

    if direction == 'LONG':
        # Target = upside
        if source.startswith('macro'):
            # Macro M bounce: target = 38.2% or 50% retracement of M drop
            m_drop = pattern_ceil - pattern_floor
            target_38 = pattern_floor + m_drop * 0.382
            target_50 = pattern_floor + m_drop * 0.500
            # Use 50% retrace for M_BUY, but cap at 65% by 1M filter later
            target = target_50
            notes.append(f"ret50%${target:.0f}")
        elif '2h' in signals and signals['2h'].get('ceil'):
            target = signals['2h']['ceil']
        elif pattern_type in ('W', 'M'):
            target = pattern_ceil
        else:
            target = price + atr * 1.5

        # Stop = downside
        if source.startswith('macro'):
            stop = pattern_floor
        elif '2h' in signals and signals['2h'].get('floor'):
            stop = signals['2h']['floor']
        elif pattern_type in ('W', 'M'):
            stop = pattern_floor
        else:
            stop = price - atr

        # 1M=M caps upside at 65%
        if '1m' in data and data['1m'] is not None and len(data['1m']['close']) > 5:
            m_letters = wt.detect_letters(
                data['1m']['high'], data['1m']['low'], data['1m']['close'],
                order=2, min_amp_pct=1
            )
            if m_letters and m_letters[-1][0] == 'M':
                gap_to_target = target - entry
                target = round(entry + gap_to_target * 0.65, 2)
                notes.append("1M=M cap65%")

    else:  # SHORT
        # Target = downside
        if source.startswith('macro'):
            # v7: Use 2h floor if available (more recent structure),
            # otherwise macro floor. Never use the macro ceiling as stop —
            # it can be months old and 5× ATR away.
            target = signals['2h'].get('floor', pattern_floor) if '2h' in signals else pattern_floor
            notes.append(f"floor${target:.0f}")
        elif '2h' in signals and signals['2h'].get('floor'):
            target = signals['2h']['floor']
        elif pattern_type in ('M', 'W'):
            target = pattern_floor
        else:
            target = price - atr * 1.5

        # Stop = upside
        if source.startswith('macro'):
            # v7: ATR-capped stop — never wider than 2× ATR.
            # Macro ceiling can be absurdly far (months-old highs).
            recent_high = signals['2h'].get('ceil', pattern_ceil) if '2h' in signals else pattern_ceil
            stop_atr = round(price + atr * 2, 2)
            stop_struct = recent_high if (recent_high and recent_high < stop_atr) else stop_atr
            stop = min(stop_atr, stop_struct)
            notes.append(f"stop${stop:.0f}")
        elif '2h' in signals and signals['2h'].get('ceil'):
            stop = signals['2h']['ceil']
        elif pattern_type in ('M', 'W'):
            stop = pattern_ceil
        else:
            stop = price + atr

        # 1M=W caps downside at 65%
        if '1m' in data and data['1m'] is not None and len(data['1m']['close']) > 5:
            m_letters = wt.detect_letters(
                data['1m']['high'], data['1m']['low'], data['1m']['close'],
                order=2, min_amp_pct=1
            )
            if m_letters and m_letters[-1][0] == 'W':
                gap_to_target = entry - target
                target = round(entry - gap_to_target * 0.65, 2)
                notes.append("1M=W cap65%")

    # Key level confirm
    level_file = STORAGE / f"levels_{ticker.lower()}.json"
    if level_file.exists():
        try:
            ldata = json.loads(level_file.read_text())
            res = ldata.get('resistance', {}).get('price', 0)
            sup = ldata.get('support', {}).get('price', 0)
            if direction == 'LONG' and res > 0:
                if abs(target - res) / res < 0.03:
                    target = min(target, res)
                    notes.append(f"res${res}")
            if direction == 'SHORT' and sup > 0:
                if abs(target - sup) / sup < 0.03:
                    target = max(target, sup)
                    notes.append(f"sup${sup}")
        except:
            pass

    # R:R check
    risk = abs(entry - stop)
    reward = abs(target - entry)
    rr = reward / risk if risk > 0 else 0
    if rr < 0.5:
        grade = 'D'
        notes.append(f"R:R{rr:.1f}!")

    # ======================================================================
    # FORMAT OUTPUT - clean binary: always a direction
    # ======================================================================
    arrow = "LONG" if direction == "LONG" else "SHORT"
    emoji = "🟢" if direction == "LONG" else "🔴"
    pattern_str = f"{pattern_type}@{pattern_pct:.0f}%" if pattern_type in ('W', 'M') else regime
    note_str = " ".join(notes) if notes else ""
    now_et = datetime.now(ET)

    output = (
        f"**{ticker}** ${price:.2f}  "
        f"{emoji} **{arrow}**  "
        f"Entry ${entry:.2f}  Target ${target:.2f}  Stop ${stop:.2f}  "
        f"**[{grade}]** {win_rate:.0%}  "
        f"({pattern_str})  "
        f"_{note_str}_"
    )

    print(output)

    # Save
    try:
        (STORAGE / f"binary_{ticker.lower()}.json").write_text(json.dumps({
            'ticker': ticker, 'price': price, 'direction': direction,
            'entry': entry, 'target': round(target, 2), 'stop': round(stop, 2),
            'grade': grade, 'win_rate': round(win_rate, 3),
            'pattern': pattern_type, 'pattern_pct': round(pattern_pct, 1),
            'regime': regime, 'source': source,
            'rsi': rsi, 'rr': round(rr, 2),
            'notes': notes, 'time': now_et.isoformat(),
        }, indent=2, default=str))
    except:
        pass

    # Alert if grade A
    if send_alerts and grade == 'A':
        try:
            from telegram_bot import send_message
            send_message(output)
        except:
            pass

    return {
        'direction': direction, 'entry': entry, 'target': round(target, 2),
        'stop': round(stop, 2), 'grade': grade, 'win_rate': win_rate,
        'pattern': pattern_type, 'pattern_pct': pattern_pct,
        'regime': regime, 'notes': notes,
    }


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--all":
        for t in wt.TICKERS:
            binary_signal(t, send_alerts="--no-send" not in sys.argv)
            print()
    else:
        t = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "WTI"
        binary_signal(t, send_alerts="--no-send" not in sys.argv)