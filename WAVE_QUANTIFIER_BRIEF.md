# Wave Quantifier — Technical Brief

## 1. How Waves Are Currently Detected

### binary_signal.py (WTI/Oil)

**Detection method:** Single-bar direction check on daily bars.

- `current_up = cur > prev_close` — a pure boolean: is the **last** daily close higher than the one before?
- "1 down" in uptrend = the most recent bar closed lower → **BUY the pullback**
- "2 up" in uptrend = the most recent bar closed higher → **SELL/take profit**
- Mirror logic for downtrend: "1 up" = SELL into bounce, "2 down" = SELL continuation

**V-shape pattern detection** (lines 167-175): Scans last 5 closes for micro-structures:
- **V-shape (1↓-2↑):** `last5[i-2] > last5[i-1] < last5[i]` — a down-then-up in consecutive triplets. Count of these bumps confidence from 7→8.
- **Inverted V (1↑-2↓):** `last5[i-2] < last5[i-1] > last5[i]` — an up-then-down. Same confidence boost.

**Trend determination** (lines 136-157): Point-scoring system on EMA stack (5/9/21), price vs EMA9/21, weekly change. Score ≥3 = UP, ≤-3 = DOWN, else SIDEWAYS.

**Critical limitation:** The "1 down" / "2 up" labeling is **not actually counting waves**. It's just checking whether the LAST bar is up or down. There is no wave-counting logic — no tracking of how many consecutive bars moved in one direction, no measurement of the pullback depth, no counting of legs.

---

### rgti_turn_detector.py — `count_wave()`

**Detection method:** Consecutive-bar direction grouping.

```python
# Walks through closes; groups consecutive same-direction bars:
for i in range(1, len(closes)):
    up = float(closes.iloc[i]) > float(closes.iloc[i-1])
    d = 'UP' if up else 'DN'
    if d == cur_dir:
        cur_count += 1
    else:
        sequences.append((cur_dir, cur_count))
        cur_dir = d; cur_count = 1
```

Produces a list like: `[('UP', 3), ('DN', 1), ('UP', 2), ('DN', 4)]`

**Wave position logic** (lines 333-366):
- `recent = sequences[-1]` = current wave leg (direction + bar count)
- `prev = sequences[-2]` = previous wave leg
- UPTREND + recent DN → `"N↓"`, signal=BUY, bias=+2 if N==1 else +1
- UPTREND + recent UP, N≥2 → `"N↑"`, signal=SELL, bias=-1
- DOWNTREND + recent UP → `"N↑"`, signal=SELL, bias=-2 if N==1 else -1
- DOWNTREND + recent DN, N≥3 → capitulation BUY, bias=+1
- Returns: sequences[-4:], trend, current_wave, wave_signal, wave_context, net_bias, EMAs

**Improvements over binary_signal.py:**
- Actually counts consecutive bars in one direction
- Provides wave_context (e.g., "1↓→2↑") showing the transition
- Keeps last 4 wave sequences for context

**Still missing (same problems as binary_signal.py):**
- No amplitude/magnitude measurement
- No duration beyond raw bar count
- No statistical history

---

## 2. What's NOT Measured (The Gaps)

| Gap | Current State | Why It Matters |
|-----|--------------|----------------|
| **Wave amplitude (%)** | Completely absent. A 0.1% dip and a 5% dip are both "1↓" | The strategy says "3-6% targets" but never measures whether pullbacks are actually 3-6% or something else entirely |
| **Wave duration (bars)** | count_wave() counts bars but binary_signal.py ignores it entirely | A 1-bar flash dip vs. a 5-bar grinding pullback behave differently |
| **Extension amplitude (%)** | "2 up" extension isn't measured — no check if it actually reaches 3-6% | The take-profit logic assumes extensions hit 3-6%, with zero evidence |
| **Failure rate** | No tracking of how often "1↓ in uptrend" bounces vs. continues into "3↓" or "4↓" | Without failure rates, confidence scores (7, 8) are arbitrary |
| **Pullback-to-extension ratio** | Not measured. Is the typical 1-down 40% of the prior 2-up? 70%? | Determines optimal stop placement — currently using flat ATR, not wave statistics |
| **Declining amplitude (trend exhaustion)** | No comparison of successive wave magnitudes | Shrinking waves = trend losing momentum (early reversal signal) |
| **Wave volume profile** | Volume measured separately (vol_ratio) but never tied to wave phase | Down-bar on high vol = distribution; up-bar on low vol = weak extension |
| **Time between turns** | Not tracked. Calendar time between wave inflections | Helps set optimal entry timing and avoid false signals |
| **Deep wave history** | count_wave() keeps 4 sequences, binary_signal.py uses 5 bars | Need full trend wave history to compute distributions |
| **Conditional statistics** | No "given UPTREND + range_pct<50, what's the typical 1↓ amplitude?" | The confidence adjustments for range position (lines 326-329) have zero statistical backing |
| **Wave failure → next wave** | If 1↓ becomes 3↓, what happens to the subsequent bounce? Not tracked | This is where trends break — the key question the user is asking |

---

## 3. Proposed Data Structure for Wave Quantifier

### 3a. Individual Wave Record

Captures one wave leg (one directional run in the sequence):

```python
@dataclass
class WaveLeg:
    # Identity
    leg_id: int              # Sequential ID in the trend
    direction: str           # 'UP' or 'DN'
    trend: str               # 'UP', 'DOWN', 'SIDEWAYS' — the prevailing trend
    
    # Timing
    start_idx: int           # Bar index where wave starts
    end_idx: int             # Bar index where wave ends
    start_ts: datetime       # Timestamp of first bar
    end_ts: datetime         # Timestamp of last bar
    duration_bars: int       # Number of consecutive bars
    duration_minutes: float  # Calendar minutes (for intraday)
    
    # Price / Amplitude
    start_price: float       # Close at wave start
    end_price: float         # Close at wave end
    extreme_price: float     # Highest high (for UP) or lowest low (for DN) within wave
    amplitude_pct: float     # (end - start) / start * 100, signed
    max_excursion_pct: float # (extreme - start) / start * 100, always positive
    
    # Context
    wave_position: str       # '1DOWN', '2UP', '3DOWN', etc. — label in the 1-down/2-up schema
    prev_wave_id: int        # ID of previous leg (for ratio calculations)
    range_pct_at_start: float  # Where price was in monthly range when wave began
    
    # Volume
    avg_volume: float        # Mean volume during this wave
    vol_vs_avg: float        # Ratio vs 20-bar average volume
    
    # Outcome (filled after wave completes + N bars)
    outcome: str             # 'completed' | 'failed' | 'extended'
    next_leg_id: int          # ID of the next wave leg
    reversal_amplitude: float  # Amplitude of the next leg (for ratio calc)
    
    # Derived (computed from history)
    pullback_pct_of_prev: float  # For pullback legs: this_amplitude / prev_wave_amplitude
    extension_ratio: float       # For extension legs: this_amplitude / prev_wave_amplitude
```

### 3b. Wave Cycle Record

Pairs a pullback with its subsequent extension — the atomic unit for the 1↓/2↑ strategy:

```python
@dataclass
class WaveCycle:
    cycle_id: int
    trend: str               # 'UP' or 'DOWN'
    
    # The pullback
    pullback: WaveLeg        # The 1-down (uptrend) or 1-up (downtrend)
    
    # The extension
    extension: WaveLeg       # The 2-up (uptrend) or 2-down (downtrend)
    
    # Cycle metrics
    pullback_amplitude: float    # %, always positive
    extension_amplitude: float  # %, always positive
    ratio_ext_to_pullback: float  # Extension / Pullback (e.g., 2.0 means extension is 2x pullback)
    
    # Failure tracking
    pullback_extended: bool      # Did the "1-down" become 3+ down? (pullback failed)
    extension_target_hit: bool  # Did the 3-6% target actually get hit?
    extension_max_pct: float    # Maximum extension before reversal
    
    # Timing
    pullback_duration_bars: int
    extension_duration_bars: int
    total_cycle_bars: int
    cycle_ratio_duration: float  # extension_bars / pullback_bars
    
    # Volume profile
    pullback_vol_ratio: float   # Volume during pullback vs avg
    extension_vol_ratio: float  # Volume during extension vs avg
    vol_imbalance: float         # extension_vol / pullback_vol (>1 = confirmation)
    
    # Context at entry
    range_pct_at_entry: float   # Monthly range position when pullback starts
    rsi5_at_entry: float
    ema_spread_at_entry: float  # (ema5 - ema9) / ema9 * 100 — trend strength
```

### 3c. Trend-Level Statistics (Aggregated)

Rolling statistics for the current trend regime:

```python
@dataclass
class TrendWaveStats:
    symbol: str
    trend: str               # 'UP' or 'DOWN'
    lookback_bars: int       # How many bars of history used
    
    # Pullback distribution (1-down in uptrend, 1-up in downtrend)
    pullback_count: int
    pullback_amplitudes: list[float]     # All observed pullback %s
    pullback_mean: float
    pullback_median: float
    pullback_std: float
    pullback_p10: float       # 10th percentile (shallow)
    pullback_p90: float       # 90th percentile (deep)
    
    # Extension distribution (2-up in uptrend, 2-down in downtrend)
    extension_count: int
    extension_amplitudes: list[float]
    extension_mean: float
    extension_median: float
    extension_std: float
    extension_p10: float
    extension_p90: float
    
    # Extension/Pullback ratio
    ratio_mean: float
    ratio_median: float
    ratio_std: float
    
    # Failure rates
    pullback_failure_rate: float   # % of "1-down" that extended to 3+ down
    extension_target_hit_rate: float  # % of extensions that reached 3% target
    extension_target6_hit_rate: float  # % that reached 6% target
    
    # Duration statistics
    pullback_bars_mean: float
    extension_bars_mean: float
    
    # Trend health
    amplitude_trend: float   # Regression slope of successive wave amplitudes
                             # Negative = waves shrinking (exhaustion)
                             # Positive = waves growing (accelerating)
    last_3_ratios: list[float]  # Recent ext/pullback ratios
    
    # Conditional statistics
    stats_by_range_zone: dict   # { '0-25': {...}, '25-50': {...}, '50-75': {...}, '75-100': {...} }
    stats_by_rsi_zone: dict     # { 'oversold': {...}, 'neutral': {...}, 'overbought': {...} }
```

### 3d. Storage Format (JSONL)

Backtest results stored as append-only log:

```
storage/wave_stats.jsonl   — one WaveCycle per line
storage/wave_legs.jsonl    — one WaveLeg per line (for drill-down)
storage/trend_stats.json   — latest TrendWaveStats (overwritten each run)
```

---

## 4. Implementation Roadmap

### Phase 1: Wave Identifier (new file: `wave_quantifier.py`)

**Input:** `closes` Series, `highs`, `lows`, `volumes` Series, `trend` string

**Core algorithm:**
1. Run count_wave()-style sequence builder to get `(direction, bar_count)` tuples
2. For each sequence, record start/end prices, compute amplitude_pct
3. Pair pullbacks with extensions → WaveCycle records
4. Track failure: if a "1-down" sequence gets extended (i.e., more down bars follow after a 1-bar bounce), mark as `pullback_extended=True`

### Phase 2: Historical Scanner

- Fetch 6-12 months of daily bars (or 2 months of 5m bars for intraday)
- Run wave identifier across entire history
- Build TrendWaveStats aggregations
- Store to JSONL for persistence

### Phase 3: Live Integration

- In `binary_signal.py`: Before generating a signal, query TrendWaveStats
- Replace hardcoded targets with statistical targets:
  - `pct_target = stats.extension_mean` instead of flat 4%
  - `pct_stop = stats.pullback_p90` instead of flat ATR
- Add failure probability to confidence:
  - `conf -= 2` if current pullback already exceeds `pullback_p90` (unusual pullback = trend might be breaking)
  - `conf += 2` if pullback is at `pullback_median` (textbook setup)

### Phase 4: Trend Break Detection

- Amplitude trend (regression slope) < 0 → waves shrinking → exhaustion warning
- Pullback failure rate rising in recent N cycles → trend weakening
- Extension/pullback ratio declining → extensions getting weaker relative to risk → stops tightening

---

## 5. Key Design Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Wave definition | Close-to-close consecutive direction | Matches existing count_wave() logic — no refactor needed |
| Pullback threshold | 1+ bars in counter-trend direction | Same as current "1 down" logic |
| Extension threshold | 2+ bars in trend direction | Same as current "2 up" logic |
| Amplitude calculation | (end_close - start_close) / start_close × 100 | Simple, matches how targets are expressed |
| Lookback for stats | 60 bars (3 months daily, 2 days 5m) | Enough cycles for statistics, recent enough to be relevant |
| Minimum sample | 10 wave cycles before reporting stats | Avoids noisy conclusions from tiny samples |
| Per-instrument stats | Yes — oil and RGTI have different wave profiles | The 3-6% oil target won't apply to RGTI (~10-15% moves) |

---

## 6. Concrete Example: What Changes in binary_signal.py

**Before (current):**
```python
if trend == "UP":
    if not current_up:
        signal = "BUY"
        target = round(cur * (1 + pct_target), 2)   # +4% hardcoded
        stop = round(cur * (1 - pct_stop), 2)        # -1.5% hardcoded
        conf = 7
```

**After (with wave quantifier):**
```python
if trend == "UP":
    if not current_up:
        signal = "BUY"
        # Statistical targets from observed waves
        target = round(cur * (1 + stats.extension_median), 2)
        stop = round(cur * (1 - stats.pullback_p90), 2)   # stop beyond 90th pct pullback
        conf = 7
        # Adjust confidence based on where current pullback sits in distribution
        current_pullback_pct = (prev_close - cur) / prev_close * 100
        if current_pullback_pct > stats.pullback_p90:
            conf -= 2   # Unusually deep pullback — trend might be breaking
        elif current_pullback_pct <= stats.pullback_median:
            conf += 1   # Textbook shallow pullback
        if stats.pullback_failure_rate > 0.3:
            conf -= 1   # Trend is failing >30% of the time
```

---

*Prepared: 2026-05-29 | Files analyzed: binary_signal.py (634 lines), rgti_turn_detector.py (835 lines)*