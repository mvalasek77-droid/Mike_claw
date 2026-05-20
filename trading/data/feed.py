"""yfinance-backed OHLC loader with on-disk parquet cache."""
from __future__ import annotations

import time
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import yfinance as yf

from ..config import CFG


def _cache_path(ticker: str, interval: str) -> Path:
    safe = ticker.replace("=", "_").replace(".", "_").replace("/", "_")
    p = CFG.data_dir / f"{safe}_{interval}.parquet"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _age_seconds(ts: pd.Timestamp) -> float:
    now = pd.Timestamp.now(tz="UTC")
    if ts.tzinfo is None:
        ts = ts.tz_localize("UTC")
    return (now - ts).total_seconds()


def fetch(ticker: str, interval: str, lookback_days: int, use_cache: bool = True, max_cache_age_sec: int = 600) -> pd.DataFrame:
    """Return OHLCV dataframe indexed by timestamp.

    Cache invalidates after `max_cache_age_sec` (default 10 minutes) so the
    30-minute bot loop always sees a recent bar.
    """
    path = _cache_path(ticker, interval)
    if use_cache and path.exists():
        try:
            cached = pd.read_parquet(path)
            if not cached.empty and _age_seconds(cached.index[-1]) < max_cache_age_sec:
                return cached
        except Exception:
            pass

    period = f"{lookback_days}d"
    df: pd.DataFrame | None = None
    for attempt in range(3):
        try:
            df = yf.Ticker(ticker).history(period=period, interval=interval, auto_adjust=False)
            if df is not None and not df.empty:
                break
        except Exception:
            pass
        time.sleep(2 ** attempt)

    if df is None or df.empty:
        if path.exists():
            return pd.read_parquet(path)
        raise RuntimeError(f"No data for {ticker} {interval}")

    df.columns = [str(c).lower() for c in df.columns]
    keep = [c for c in ("open", "high", "low", "close", "volume") if c in df.columns]
    df = df[keep].dropna()
    try:
        df.to_parquet(path)
    except Exception:
        pass
    return df


def latest_price(ticker: str, interval: str = "1m") -> float:
    df = fetch(ticker, interval, lookback_days=2, max_cache_age_sec=60)
    return float(df["close"].iloc[-1])
