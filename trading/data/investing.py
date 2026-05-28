"""Real-time WTI price from Investing.com.

Investing.com shows live CME Globex prices with ~15 sec delay,
much fresher than yfinance which can lag 5-15 minutes.

Uses web scraping with proper headers to avoid blocking.
"""
from __future__ import annotations

import re
import time
from functools import lru_cache

import requests
from bs4 import BeautifulSoup

_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Cache-Control": "no-cache",
}

_WTI_URL = "https://www.investing.com/commodities/crude-oil"
_CACHE_SECONDS = 15  # Don't hit investing.com more than once per 15 sec

_last_fetch = 0.0
_last_price = None


def wti_live() -> float | None:
    """Get real-time WTI price from Investing.com.
    
    Returns the last traded price, or None if unavailable.
    Caches for 15 seconds to avoid rate limiting.
    """
    global _last_fetch, _last_price
    
    # Cache check
    now = time.monotonic()
    if _last_price is not None and (now - _last_fetch) < _CACHE_SECONDS:
        return _last_price
    
    try:
        r = requests.get(_WTI_URL, headers=_HEADERS, timeout=15)
        if r.status_code != 200:
            return _last_price
        
        soup = BeautifulSoup(r.text, "html.parser")
        
        # Find the big price — it's in a span with class containing 'text-5xl' and 'font-bold'
        # Also has classes like 'text-[#232526]' or similar
        candidates = []
        for tag in soup.find_all(["span", "div"]):
            cls = " ".join(tag.get("class", []))
            text = tag.get_text(strip=True)
            
            # Must look like a price (98.XX pattern)
            if re.match(r"^\d{2,3}\.\d{2}$", text):
                # Prefer tags with font-bold or text-5xl (the big price display)
                weight = 0
                if "font-bold" in cls:
                    weight += 2
                if "text-5xl" in cls or "text-[42px]" in cls:
                    weight += 3
                if "text-[#232526]" in cls:
                    weight += 1
                candidates.append((weight, float(text)))
        
        if candidates:
            # Pick the one with highest weight (the big displayed price)
            candidates.sort(key=lambda x: x[0], reverse=True)
            _last_price = candidates[0][1]
            _last_fetch = now
            return _last_price
            
    except Exception:
        pass
    
    return _last_price


def wti_change() -> dict:
    """Get WTI price + change from Investing.com."""
    try:
        r = requests.get(_WTI_URL, headers=_HEADERS, timeout=15)
        if r.status_code != 200:
            return {"price": wti_live(), "change": None, "change_pct": None}
        
        soup = BeautifulSoup(r.text, "html.parser")
        
        # Find price
        price = None
        for tag in soup.find_all(["span", "div"]):
            cls = " ".join(tag.get("class", []))
            text = tag.get_text(strip=True)
            if re.match(r"^\d{2,3}\.\d{2}$", text) and ("font-bold" in cls or "text-5xl" in cls):
                price = float(text)
                break
        
        if price is None:
            price = wti_live()
        
        # Find change (looks like "-5.81(-5.57%)")
        change = None
        change_pct = None
        for tag in soup.find_all(["span", "div"]):
            text = tag.get_text(strip=True)
            m = re.match(r"^([+-]?\d+\.\d{2})\(([+-]?\d+\.\d{2})%\)$", text)
            if m:
                change = float(m.group(1))
                change_pct = float(m.group(2))
                break
        
        return {
            "price": price,
            "change": change,
            "change_pct": change_pct,
        }
        
    except Exception:
        return {"price": wti_live(), "change": None, "change_pct": None}