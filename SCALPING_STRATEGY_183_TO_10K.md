# $183 → $10K in 90 Days: Active Scalping Strategy

## The Math
- Start: $183
- Target: $10,000  
- Timeline: 60 trading days (~3 months)
- **Daily return needed: 6.9%**

## Compound Path
| Day | Balance | Milestone |
|-----|---------|-----------|
| 1 | $195 | First scalp |
| 5 | $255 | |
| 10 | $356 | |
| 15 | $498 | Phase 1 done |
| 20 | $694 | |
| 30 | $1,353 | Phase 2 done |
| 40 | $2,635 | |
| 50 | $5,133 | |
| 60 | $10,000 | 🎯 |

## Daily Target: 7% (2-3 trades averaging 3-4% each)

## Why 7% is achievable:
- RGTI avg daily move: 7.2%
- HOU avg daily move: 6.4%  
- SOXS avg daily move: 10.2%
- 85% of RGTI days have 3%+ moves
- 75% of HOU days have 3%+ moves

## PHASE 1: $183 → $500 (Days 1-15)
Goal: 5.2%/day

### Instrument: RGTI (7 shares @ $24.70 = $173)
Why RGTI: Most volatile, biggest daily moves, 85% of days move 3%+

### Daily Routine:
1. **6:30 AM PT** — Check pre-market, pick direction
2. **6:30-7:30** — Scalp #1 (ride opening momentum, 3-4% target)
3. **9:30-11:00** — Scalp #2 (morning reversal or continuation, 3-4%)
4. **12:45 PM** — Final trade/scalp or close
5. **After hours** — Review, plan next day

### Entry Rules (RGTI):
- **LONG** when: EMA5 > EMA13 + price > VWAP + volume > avg
- **SHORT** when: EMA5 < EMA13 + price < VWAP + volume > avg
- **Never** enter without 2+ confirming signals
- **Target**: 3-4% gain or EMA5 cross, whichever comes first
- **Hard stop**: -2% (never let a loser run)

### Risk Management (Phase 1):
- Max position: ALL IN (7 shares — no diversification at $183)
- Max daily loss: $15 (8%) — if you lose this, STOP for the day
- 2 consecutive losses = stop for the day
- Never average down on a losing position

## PHASE 2: $500 → $2,000 (Days 16-40)
Goal: 5.7%/day

### Expand to RGTI + HOU/HOD rotation:
- RGTI for momentum plays
- HOU when oil trending UP (WTI > daily EMA9)
- HOD when oil trending DOWN (WTI < daily EMA9)

### Position sizes:
- $500 → buy 20 RGTI shares OR 21 HOU shares
- Still all-in on one trade at a time

### New rule: Can take 2 trades simultaneously if both signal

## PHASE 3: $2,000 → $10,000 (Days 41-60)
Goal: 6.6%/day

### Full arsenal:
- RGTI (momentum)
- HOU/HOD (oil rotation)  
- SOXS/SOXL (semiconductor plays, 10% avg move!)

### Position sizes:
- $2,000 → 80 RGTI shares
- Split: 50% main trade + 50% second trade

### Can consider 0DTE options on SPY/QQQ:
- 1 contract ≈ $30-50
- 10-50x leverage on small S&P moves
- Only with $2K+ account (keep $1,500 in shares as backup)

## SCALPING RULES (THE DISCIPLINE):

### ✅ DO:
1. Trade the first 30 min and last 30 min (highest volume/moves)
2. Always have a target AND stop before entering
3. Take profit at target — don't get greedy
4. Close everything before 1:00 PM PT
5. Review every trade at end of day

### ❌ DON'T:
1. Don't chase — if you miss the entry, wait for next setup
2. Don't revenge trade after a loss
3. Don't hold losers hoping they bounce
4. Don't trade sideways markets (wait for direction)
5. Don't average down ever

## THE DAILY FLOW:

### Morning Scalp (6:30-7:30 AM PT):
- Check WTI pre-market direction
- Check RGTI pre-market gap
- Enter on 5-min candle confirmation
- Target: 3-4% 
- Stop: 2%
- TIME STOP: If no move in 15 min, exit

### Midday Scalp (10:00-11:30 AM PT):  
- Reassess trend
- New entry or continuation
- Target: 3-4%
- Stop: 2%

### Power Hour (12:30-1:00 PM PT):
- Final trade or close positions
- Don't start new trades after 12:45 PM

## TRACKING:
Log every trade in trading/storage/trade_log.jsonl:
- Entry time, price, shares
- Exit time, price, shares
- P&L ($) and (%)
- Running balance

## AUTOMATED ALERTS (running):
1. RGTI Turn Detector — every 2 min
2. RGTI Strong Buy — every 2 min  
3. Oil Bot — every 30 min

These alert you, YOU decide when to pull the trigger.