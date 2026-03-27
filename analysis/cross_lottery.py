"""
Cross-Lottery Transfer Analysis
Finds patterns that transfer between LottoMax, Lotto649, BC49.
When a pattern appears in one lottery, it may echo in another.
"""

from collections import Counter, defaultdict
from datetime import datetime, timedelta

import numpy as np

from config import LOTTERIES, STRATEGY


class CrossLotteryAnalyzer:
    """
    Obsessively tracks how patterns migrate between lotteries.
    If lottery A shows a pattern today, will lottery B show it tomorrow?
    We MUST find out. There is no alternative.
    """

    def __init__(self):
        self.shared_number_history = defaultdict(list)
        self.transfer_scores = defaultdict(float)
        self.echo_patterns = []

    def analyze_transfers(self, all_draws):
        """
        Analyze all cross-lottery number transfers.
        all_draws: dict of {lottery_id: [draws]}
        """
        results = {
            "same_day_overlaps": self._same_day_overlap(all_draws),
            "next_day_echoes": self._next_day_echoes(all_draws),
            "weekly_rhythm": self._weekly_rhythm_transfer(all_draws),
            "hot_number_migration": self._hot_number_migration(all_draws),
            "pair_transfer": self._pair_transfer(all_draws),
        }
        return results

    def _same_day_overlap(self, all_draws):
        """Find numbers that appear in multiple lotteries on the same date."""
        date_draws = defaultdict(dict)
        for lid, draws in all_draws.items():
            for d in draws:
                date_draws[d["date"]][lid] = set(d["numbers"])

        overlaps = []
        for date, lottery_nums in date_draws.items():
            lids = list(lottery_nums.keys())
            for i in range(len(lids)):
                for j in range(i + 1, len(lids)):
                    shared = lottery_nums[lids[i]] & lottery_nums[lids[j]]
                    if shared:
                        overlaps.append({
                            "date": date,
                            "lotteries": [lids[i], lids[j]],
                            "shared_numbers": sorted(shared),
                        })

        # Rate
        total_dates = len(date_draws)
        overlap_dates = len(set(o["date"] for o in overlaps))
        return {
            "overlap_rate": overlap_dates / max(total_dates, 1),
            "total_overlaps": len(overlaps),
            "recent_overlaps": overlaps[:20],
            "most_shared_numbers": Counter(
                n for o in overlaps for n in o["shared_numbers"]
            ).most_common(15),
        }

    def _next_day_echoes(self, all_draws):
        """
        When lottery A draws on day X, do those numbers echo in lottery B on day X+1?
        This is the DAY BEFORE pattern across lotteries.
        """
        # Build date index
        date_index = defaultdict(dict)
        for lid, draws in all_draws.items():
            for d in draws:
                date_index[d["date"]][lid] = set(d["numbers"])

        echo_hits = Counter()
        echo_total = 0
        echo_details = []

        sorted_dates = sorted(date_index.keys())
        for i in range(len(sorted_dates) - 1):
            today = sorted_dates[i]
            tomorrow = sorted_dates[i + 1]

            # Check if the dates are actually consecutive
            try:
                d1 = datetime.strptime(today, "%Y-%m-%d")
                d2 = datetime.strptime(tomorrow, "%Y-%m-%d")
                if (d2 - d1).days > 2:
                    continue
            except ValueError:
                continue

            for lid_today, nums_today in date_index[today].items():
                for lid_tomorrow, nums_tomorrow in date_index[tomorrow].items():
                    if lid_today == lid_tomorrow:
                        continue
                    echo_total += 1
                    shared = nums_today & nums_tomorrow
                    # Also check adjacents
                    adjacent_shared = set()
                    for nt in nums_today:
                        for nm in nums_tomorrow:
                            if abs(nt - nm) == 1:
                                adjacent_shared.add((nt, nm))

                    if shared or adjacent_shared:
                        echo_hits[f"{lid_today}->{lid_tomorrow}"] += 1
                        echo_details.append({
                            "from": lid_today,
                            "to": lid_tomorrow,
                            "date_from": today,
                            "date_to": tomorrow,
                            "direct_shared": sorted(shared),
                            "adjacent_shared": list(adjacent_shared)[:5],
                        })

        return {
            "echo_rate_by_pair": {k: v / max(echo_total // max(len(echo_hits), 1), 1)
                                  for k, v in echo_hits.items()},
            "total_echoes": sum(echo_hits.values()),
            "recent_echoes": echo_details[:15],
        }

    def _weekly_rhythm_transfer(self, all_draws):
        """Analyze if numbers follow a weekly rhythm across lotteries."""
        weekly_groups = defaultdict(lambda: defaultdict(list))

        for lid, draws in all_draws.items():
            for d in draws:
                try:
                    dt = datetime.strptime(d["date"], "%Y-%m-%d")
                    week_key = dt.strftime("%Y-W%W")
                    weekly_groups[week_key][lid].extend(d["numbers"])
                except ValueError:
                    continue

        # For each week, find numbers appearing across multiple lotteries
        weekly_shared = []
        for week, lid_nums in weekly_groups.items():
            all_nums_by_lottery = {lid: Counter(nums) for lid, nums in lid_nums.items()}
            for n in range(1, 51):
                appearing_in = [lid for lid, counter in all_nums_by_lottery.items() if counter.get(n, 0) > 0]
                if len(appearing_in) >= 2:
                    weekly_shared.append({"week": week, "number": n, "lotteries": appearing_in})

        return {
            "weekly_cross_appearances": len(weekly_shared),
            "sample": weekly_shared[:20],
        }

    def _hot_number_migration(self, all_draws):
        """Track when a number becomes hot in one lottery, does it migrate to others?"""
        # Calculate 10-draw rolling frequency for each lottery
        hot_windows = defaultdict(lambda: defaultdict(list))

        for lid, draws in all_draws.items():
            for i in range(len(draws) - 10):
                window = draws[i:i + 10]
                freq = Counter()
                for d in window:
                    freq.update(d["numbers"])
                for n, count in freq.items():
                    if count >= 4:  # Hot if appears 4+ times in 10 draws
                        hot_windows[lid][n].append(i)

        # Cross-reference: when a number is hot in lottery A, is it also hot in B?
        migrations = []
        lids = list(all_draws.keys())
        for i in range(len(lids)):
            for j in range(len(lids)):
                if i == j:
                    continue
                lid_a = lids[i]
                lid_b = lids[j]
                for n in set(hot_windows[lid_a].keys()) & set(hot_windows[lid_b].keys()):
                    migrations.append({
                        "number": n,
                        "hot_in": lid_a,
                        "also_hot_in": lid_b,
                    })

        return {
            "migration_count": len(migrations),
            "migrating_numbers": Counter(m["number"] for m in migrations).most_common(15),
        }

    def _pair_transfer(self, all_draws):
        """Do number pairs that appear in one lottery also appear in others?"""
        from itertools import combinations

        pair_by_lottery = defaultdict(Counter)
        for lid, draws in all_draws.items():
            for d in draws:
                for pair in combinations(sorted(d["numbers"]), 2):
                    pair_by_lottery[lid][pair] += 1

        # Find pairs shared across lotteries
        shared_pairs = Counter()
        lids = list(all_draws.keys())
        for pair in set().union(*[set(pc.keys()) for pc in pair_by_lottery.values()]):
            appearing_in = [lid for lid in lids if pair_by_lottery[lid].get(pair, 0) >= 2]
            if len(appearing_in) >= 2:
                shared_pairs[pair] += sum(pair_by_lottery[lid][pair] for lid in appearing_in)

        return {
            "cross_lottery_pairs": len(shared_pairs),
            "top_shared_pairs": [{"pair": list(p), "total_count": c}
                                 for p, c in shared_pairs.most_common(20)],
        }

    def get_transfer_signals(self, target_lottery, all_draws, latest_other_draws):
        """
        Get actionable signals from other lotteries for predicting the target.
        latest_other_draws: most recent draw from each other lottery
        """
        signals = {
            "numbers_from_other_lotteries": set(),
            "adjacent_signals": set(),
            "hot_migrants": set(),
        }

        cfg = LOTTERIES[target_lottery]
        lo, hi = cfg["number_range"]

        for lid, draw in latest_other_draws.items():
            if lid == target_lottery:
                continue
            for n in draw["numbers"]:
                if lo <= n <= hi:
                    signals["numbers_from_other_lotteries"].add(n)
                    signals["adjacent_signals"].add(max(lo, n - 1))
                    signals["adjacent_signals"].add(min(hi, n + 1))

        # Convert sets to sorted lists
        signals["numbers_from_other_lotteries"] = sorted(signals["numbers_from_other_lotteries"])
        signals["adjacent_signals"] = sorted(signals["adjacent_signals"])

        return signals
