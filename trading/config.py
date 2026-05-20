"""Single source of truth for tickers, parameters, risk limits, schedule."""
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class TradingConfig:
    # ---- Universe ----
    longs_ticker: str = "HOU.TO"       # Horizons BetaPro Crude Oil 2x Bull (TSX)
    shorts_ticker: str = "HOD.TO"      # Horizons BetaPro Crude Oil 2x Bear (TSX)
    underlying_ticker: str = "CL=F"    # WTI front-month — primary signal source
    brent_ticker: str = "BZ=F"         # Brent front-month
    intl_proxy: str = "BNO"            # US Brent ETF for overnight monitoring

    # ---- Bars / cadence ----
    bar_interval: str = "30m"          # 30-minute alerts as requested
    daily_interval: str = "1d"
    history_days_intraday: int = 60
    history_days_daily: int = 1500
    poll_seconds: int = 60 * 30        # 30-minute cycle

    # ---- Trendline detection (wick-based pivots) ----
    pivot_left: int = 3
    pivot_right: int = 3
    min_pivots_for_line: int = 3
    trendline_lookback_pivots: int = 8
    break_atr_buffer: float = 0.5

    # ---- Regime classifier ----
    adx_period: int = 14
    adx_trend_threshold: float = 25.0  # tightened per retail consensus
    realized_vol_window: int = 20

    # ---- Indicators ----
    ema_fast: int = 9
    ema_slow: int = 21
    ema_trend: int = 50
    rsi_period: int = 14
    macd_fast: int = 12
    macd_slow: int = 26
    macd_signal: int = 9
    atr_period: int = 14

    # ---- Strategy parameters ----
    tsmom_lookback_days: int = 252     # AQR 12-month time-series momentum
    donchian_entry: int = 20           # Turtle entry channel
    donchian_exit: int = 10
    mean_revert_z: float = 2.0
    beta_window_bars: int = 100        # rolling regression window for beta

    # ---- Account / risk ----
    account_size_cad: float = 180.0    # honest small-account default
    target_annual_vol: float = 0.30
    max_position_fraction: float = 0.95  # tiny account: spend almost all on one position
    daily_loss_cap_pct: float = 0.05     # 5% = ~$9 of $180; tighter to preserve seed
    atr_stop_mult: float = 1.5
    max_hold_bars: int = 13              # ~6.5h = full TSX session of 30m bars
    max_hold_days: int = 1               # leveraged ETF decay: never hold overnight

    # ---- Economic viability gate ($180-aware) ----
    min_expected_move_pct: float = 0.008   # 0.8% net of 0.5% round-trip slippage
    min_units: int = 1                     # cannot trade fractional shares on Mogo
    slippage_pct: float = 0.005            # 0.5% reality on HOU/HOD bid-ask
    mogo_commission: float = 0.0           # Mogo Trade is commission-free
    min_signal_confidence: float = 0.30    # below this, force STAY_OUT

    # ---- Connors RSI(2) (Larry Connors short-term mean-reversion) ----
    connors_rsi_period: int = 2
    connors_oversold: float = 10.0
    connors_overbought: float = 90.0

    # ---- Event blackouts ----
    eia_blackout_minutes: int = 20         # +/- minutes around EIA Wed 10:30 ET

    # ---- Execution / alerts ----
    alert_channel: str = "console"     # console | file | webhook
    alert_webhook_url: str | None = None
    paper_starting_cash: float = 180.0

    # ---- Schedule (TSX) ----
    tsx_open: str = "09:30"
    tsx_close: str = "16:00"
    timezone: str = "America/Toronto"

    # ---- Persistence ----
    data_dir: Path = field(default_factory=lambda: Path("trading/storage/cache"))
    journal_dir: Path = field(default_factory=lambda: Path("trading/storage/journal"))
    state_dir: Path = field(default_factory=lambda: Path("trading/storage/state"))


CFG = TradingConfig()
