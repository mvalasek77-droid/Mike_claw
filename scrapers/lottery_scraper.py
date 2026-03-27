"""
Lottery Data Scraper
Fetches historical draw data from BCLC/PlayNow and fallback sources.
Stores results as CSV in the data/ directory.
"""

import csv
import json
import os
import re
import time
from datetime import datetime, timedelta
from pathlib import Path

import requests
from bs4 import BeautifulSoup

from config import DATA_DIR, LOTTERIES


class LotteryScraper:
    """Scrapes and manages historical lottery draw data."""

    HEADERS = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }

    def __init__(self):
        os.makedirs(DATA_DIR, exist_ok=True)

    def fetch_all(self):
        """Fetch data for all configured lotteries."""
        results = {}
        for lottery_id, cfg in LOTTERIES.items():
            print(f"[SCRAPER] Fetching {cfg['name']}...")
            draws = self._fetch_lottery(lottery_id, cfg)
            if draws:
                self._save_draws(lottery_id, draws)
                results[lottery_id] = len(draws)
                print(f"[SCRAPER] {cfg['name']}: {len(draws)} draws loaded.")
            else:
                print(f"[SCRAPER] {cfg['name']}: Using cached data.")
                results[lottery_id] = self._count_cached(lottery_id)
        return results

    def _fetch_lottery(self, lottery_id, cfg):
        """Try primary URL, then backup, then return cached data."""
        draws = self._try_playnow_api(lottery_id, cfg)
        if not draws and cfg.get("backup_url"):
            draws = self._try_backup_scrape(lottery_id, cfg)
        return draws

    def _try_playnow_api(self, lottery_id, cfg):
        """Attempt to fetch from PlayNow JSON API."""
        draws = []
        try:
            # Fetch recent draws
            for page in range(1, 20):
                url = f"{cfg['url']}?page={page}&pageSize=50"
                resp = requests.get(url, headers=self.HEADERS, timeout=15)
                if resp.status_code != 200:
                    break
                data = resp.json()
                if not data:
                    break
                for draw in data if isinstance(data, list) else data.get("draws", []):
                    parsed = self._parse_playnow_draw(draw, cfg)
                    if parsed:
                        draws.append(parsed)
                time.sleep(0.5)
        except Exception as e:
            print(f"[SCRAPER] PlayNow API failed for {lottery_id}: {e}")
        return draws

    def _parse_playnow_draw(self, draw, cfg):
        """Parse a draw object from PlayNow API."""
        try:
            date_str = draw.get("drawDate", draw.get("date", ""))
            if not date_str:
                return None
            # Normalize date
            for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d", "%B %d, %Y"):
                try:
                    date = datetime.strptime(date_str[:19], fmt)
                    break
                except ValueError:
                    continue
            else:
                return None

            numbers = draw.get("numbers", draw.get("mainNumbers", []))
            if isinstance(numbers, str):
                numbers = [int(x) for x in re.findall(r'\d+', numbers)]
            else:
                numbers = [int(n) if isinstance(n, (int, float)) else int(n.get("value", n.get("number", 0))) for n in numbers]

            bonus = draw.get("bonusNumber", draw.get("bonus", None))
            if isinstance(bonus, dict):
                bonus = bonus.get("value", bonus.get("number"))
            bonus = int(bonus) if bonus else None

            return {
                "date": date.strftime("%Y-%m-%d"),
                "numbers": sorted(numbers[:cfg["numbers_picked"]]),
                "bonus": bonus,
            }
        except Exception:
            return None

    def _try_backup_scrape(self, lottery_id, cfg):
        """Scrape from backup HTML source."""
        draws = []
        try:
            resp = requests.get(cfg["backup_url"], headers=self.HEADERS, timeout=15)
            if resp.status_code != 200:
                return draws
            soup = BeautifulSoup(resp.text, "lxml")
            rows = soup.select("table tr, .draw-result, .result-row")
            for row in rows:
                cells = row.select("td, .number, .ball")
                if len(cells) >= cfg["numbers_picked"]:
                    nums = []
                    for c in cells:
                        text = c.get_text(strip=True)
                        if text.isdigit():
                            nums.append(int(text))
                    if len(nums) >= cfg["numbers_picked"]:
                        date_cell = row.select_one(".date, td:first-child")
                        date_str = date_cell.get_text(strip=True) if date_cell else ""
                        draws.append({
                            "date": date_str,
                            "numbers": sorted(nums[:cfg["numbers_picked"]]),
                            "bonus": nums[cfg["numbers_picked"]] if len(nums) > cfg["numbers_picked"] else None,
                        })
        except Exception as e:
            print(f"[SCRAPER] Backup scrape failed for {lottery_id}: {e}")
        return draws

    def _save_draws(self, lottery_id, draws):
        """Save draws to CSV, merging with existing data."""
        filepath = os.path.join(DATA_DIR, f"{lottery_id}.csv")
        existing = self._load_draws(lottery_id)
        existing_dates = {d["date"] for d in existing}

        new_draws = [d for d in draws if d["date"] not in existing_dates]
        all_draws = existing + new_draws
        all_draws.sort(key=lambda d: d["date"], reverse=True)

        with open(filepath, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["date", "numbers", "bonus"])
            for d in all_draws:
                writer.writerow([d["date"], json.dumps(d["numbers"]), d.get("bonus", "")])

    def load_draws(self, lottery_id):
        """Public interface to load draws for a lottery."""
        return self._load_draws(lottery_id)

    def _load_draws(self, lottery_id):
        """Load draws from CSV file."""
        filepath = os.path.join(DATA_DIR, f"{lottery_id}.csv")
        draws = []
        if not os.path.exists(filepath):
            return draws
        with open(filepath, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    draws.append({
                        "date": row["date"],
                        "numbers": json.loads(row["numbers"]),
                        "bonus": int(row["bonus"]) if row.get("bonus") and row["bonus"] != "" else None,
                    })
                except (json.JSONDecodeError, ValueError):
                    continue
        return draws

    def _count_cached(self, lottery_id):
        """Count cached draws."""
        return len(self._load_draws(lottery_id))

    def seed_sample_data(self):
        """Generate realistic sample historical data for development/testing."""
        import random
        print("[SCRAPER] Seeding sample historical data for all lotteries...")

        for lottery_id, cfg in LOTTERIES.items():
            draws = []
            lo, hi = cfg["number_range"]
            n_pick = cfg["numbers_picked"]
            # Generate 200 draws going back ~2 years
            base_date = datetime(2026, 3, 27)
            draw_days_map = {
                "Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3,
                "Friday": 4, "Saturday": 5, "Sunday": 6
            }
            target_days = [draw_days_map[d] for d in cfg["draw_days"]]

            date = base_date
            count = 0
            while count < 200:
                if date.weekday() in target_days:
                    nums = sorted(random.sample(range(lo, hi + 1), n_pick))
                    bonus = random.randint(lo, hi)
                    while bonus in nums:
                        bonus = random.randint(lo, hi)
                    draws.append({
                        "date": date.strftime("%Y-%m-%d"),
                        "numbers": nums,
                        "bonus": bonus,
                    })
                    count += 1
                date -= timedelta(days=1)

            # Now inject realistic patterns to make the bot discover them:
            # Pattern 1: Every ~2nd draw shares a number with 2 draws ahead
            for i in range(0, len(draws) - 4, 2):
                shared = random.choice(draws[i]["numbers"])
                future = draws[i + 2]["numbers"]
                if shared not in future:
                    replace_idx = random.randint(0, len(future) - 1)
                    future[replace_idx] = shared
                    draws[i + 2]["numbers"] = sorted(future)

            # Pattern 2 (lotto649 special): prior draw always has 1 match or adjacent
            if cfg.get("prior_draw_rule"):
                for i in range(len(draws) - 1):
                    current = draws[i]["numbers"]
                    prior = draws[i + 1]["numbers"]
                    # Check if any number matches or is adjacent
                    has_link = False
                    for n in current:
                        for p in prior:
                            if abs(n - p) <= 1:
                                has_link = True
                                break
                        if has_link:
                            break
                    if not has_link:
                        # Force a link
                        donor = random.choice(prior)
                        adj = donor + random.choice([-1, 0, 1])
                        adj = max(lo, min(hi, adj))
                        replace_idx = random.randint(0, len(current) - 1)
                        current[replace_idx] = adj
                        draws[i]["numbers"] = sorted(current)

            # Pattern 3: Cross-lottery - inject some shared numbers across lotteries
            # (handled after all lotteries are seeded)

            self._save_draws(lottery_id, draws)
            print(f"[SCRAPER] Seeded {len(draws)} draws for {cfg['name']}")

        # Cross-lottery injection: share some hot numbers between same-day lotteries
        self._inject_cross_lottery_patterns()

    def _inject_cross_lottery_patterns(self):
        """Inject cross-lottery shared patterns into seeded data."""
        import random
        all_draws = {}
        for lid in LOTTERIES:
            all_draws[lid] = self._load_draws(lid)

        # Find overlapping dates between lotto649 and bc49 (both Wed/Sat)
        dates_649 = {d["date"]: d for d in all_draws.get("lotto649", [])}
        dates_bc49 = {d["date"]: d for d in all_draws.get("bc49", [])}
        common_dates = set(dates_649.keys()) & set(dates_bc49.keys())

        for date in list(common_dates)[:50]:  # First 50 overlapping dates
            if random.random() < 0.4:  # 40% chance of shared number
                d649 = dates_649[date]
                dbc49 = dates_bc49[date]
                shared = random.choice(d649["numbers"])
                if shared not in dbc49["numbers"] and shared <= 49:
                    idx = random.randint(0, len(dbc49["numbers"]) - 1)
                    dbc49["numbers"][idx] = shared
                    dbc49["numbers"] = sorted(dbc49["numbers"])

        # Save updated data
        for lid in ["lotto649", "bc49"]:
            if lid in all_draws:
                self._save_draws(lid, all_draws[lid])


if __name__ == "__main__":
    scraper = LotteryScraper()
    scraper.seed_sample_data()
    results = scraper.fetch_all()
    print(f"\n[SCRAPER] Summary: {results}")
