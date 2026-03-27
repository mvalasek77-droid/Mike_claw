"""
Core Pattern Engine
Detects pairs, triplets, adjacents, frequency distributions,
hot/cold numbers, gap analysis, and positional patterns.
"""

import json
from collections import Counter, defaultdict
from itertools import combinations

import numpy as np

from config import LOTTERIES, STRATEGY


class PatternEngine:
    """The obsessive pattern detector. It never stops looking."""

    def __init__(self):
        self.pair_db = defaultdict(lambda: defaultdict(int))
        self.triplet_db = defaultdict(lambda: defaultdict(int))
        self.adjacent_db = defaultdict(lambda: defaultdict(int))
        self.frequency_db = defaultdict(lambda: Counter())
        self.gap_db = defaultdict(lambda: defaultdict(list))
        self.positional_db = defaultdict(lambda: defaultdict(lambda: Counter()))
        self.consecutive_db = defaultdict(list)
        self.sum_db = defaultdict(list)
        self.last_seen = defaultdict(lambda: defaultdict(int))
        self.transition_matrix = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))

    def analyze(self, lottery_id, draws, depth=None):
        """
        Run EVERY analysis on the draw history. Leave no stone unturned.
        This is not optional. This is survival.
        """
        if not draws:
            return {}

        depth = depth or STRATEGY["lookback_window"]
        recent = draws[:depth]

        results = {
            "pairs": self._analyze_pairs(lottery_id, recent),
            "triplets": self._analyze_triplets(lottery_id, recent),
            "adjacents": self._analyze_adjacents(lottery_id, recent),
            "frequency": self._analyze_frequency(lottery_id, recent),
            "gaps": self._analyze_gaps(lottery_id, recent),
            "positional": self._analyze_positional(lottery_id, recent),
            "consecutives": self._analyze_consecutives(lottery_id, recent),
            "sums": self._analyze_sums(lottery_id, recent),
            "transitions": self._analyze_transitions(lottery_id, recent),
            "hot_cold": self._analyze_hot_cold(lottery_id, recent),
            "day_before_patterns": self._analyze_day_before(lottery_id, recent),
            "alternating_links": self._analyze_alternating_future_links(lottery_id, recent),
            "prior_draw_links": self._analyze_prior_draw_links(lottery_id, recent),
        }
        return results

    def _analyze_pairs(self, lottery_id, draws):
        """Find all number pairs and their co-occurrence frequency."""
        pair_counts = Counter()
        for draw in draws:
            nums = draw["numbers"]
            for pair in combinations(nums, 2):
                pair_counts[pair] += 1

        self.pair_db[lottery_id] = pair_counts
        top_pairs = pair_counts.most_common(30)
        return {
            "top_pairs": [{"pair": list(p), "count": c} for p, c in top_pairs],
            "total_unique_pairs": len(pair_counts),
            "avg_pair_frequency": np.mean(list(pair_counts.values())) if pair_counts else 0,
        }

    def _analyze_triplets(self, lottery_id, draws):
        """Find all number triplets and their co-occurrence frequency."""
        triplet_counts = Counter()
        for draw in draws:
            nums = draw["numbers"]
            for triplet in combinations(nums, 3):
                triplet_counts[triplet] += 1

        self.triplet_db[lottery_id] = triplet_counts
        top_triplets = triplet_counts.most_common(20)
        return {
            "top_triplets": [{"triplet": list(t), "count": c} for t, c in top_triplets],
            "total_unique_triplets": len(triplet_counts),
        }

    def _analyze_adjacents(self, lottery_id, draws):
        """
        Analyze adjacent number patterns:
        - Numbers that are numerically adjacent (e.g., 14, 15)
        - Numbers adjacent to previous draw numbers (+/- 1, +/- 2)
        """
        adjacent_in_draw = []  # How often draws contain consecutive numbers
        adjacent_across_draws = Counter()  # How often a number is +/-1 from prior draw

        for i, draw in enumerate(draws):
            nums = sorted(draw["numbers"])
            # Count consecutive pairs within this draw
            consec_count = sum(1 for j in range(len(nums) - 1) if nums[j + 1] - nums[j] == 1)
            adjacent_in_draw.append(consec_count)

            # Compare to previous draw
            if i + 1 < len(draws):
                prior = draws[i + 1]["numbers"]
                for n in nums:
                    for p in prior:
                        diff = abs(n - p)
                        if 0 < diff <= 2:
                            adjacent_across_draws[(p, n)] += 1

        self.adjacent_db[lottery_id] = adjacent_across_draws
        top_adjacent = adjacent_across_draws.most_common(20)

        return {
            "avg_consecutive_in_draw": np.mean(adjacent_in_draw) if adjacent_in_draw else 0,
            "max_consecutive_in_draw": max(adjacent_in_draw) if adjacent_in_draw else 0,
            "top_cross_draw_adjacents": [{"from_to": list(k), "count": v} for k, v in top_adjacent],
            "cross_draw_adjacent_rate": len([a for a in adjacent_in_draw if a > 0]) / max(len(adjacent_in_draw), 1),
        }

    def _analyze_frequency(self, lottery_id, draws):
        """Overall number frequency analysis."""
        freq = Counter()
        for draw in draws:
            freq.update(draw["numbers"])

        self.frequency_db[lottery_id] = freq
        cfg = LOTTERIES[lottery_id]
        lo, hi = cfg["number_range"]
        all_nums = list(range(lo, hi + 1))

        freq_list = [(n, freq.get(n, 0)) for n in all_nums]
        freq_list.sort(key=lambda x: x[1], reverse=True)

        return {
            "most_common": freq_list[:15],
            "least_common": freq_list[-15:],
            "mean_frequency": np.mean([f for _, f in freq_list]),
            "std_frequency": np.std([f for _, f in freq_list]),
        }

    def _analyze_gaps(self, lottery_id, draws):
        """How many draws since each number last appeared."""
        cfg = LOTTERIES[lottery_id]
        lo, hi = cfg["number_range"]
        current_gaps = {}

        for n in range(lo, hi + 1):
            for i, draw in enumerate(draws):
                if n in draw["numbers"]:
                    current_gaps[n] = i
                    break
            else:
                current_gaps[n] = len(draws)

        self.last_seen[lottery_id] = current_gaps
        overdue = [(n, g) for n, g in current_gaps.items()]
        overdue.sort(key=lambda x: x[1], reverse=True)

        avg_gap = np.mean(list(current_gaps.values()))
        return {
            "most_overdue": overdue[:15],
            "least_overdue": overdue[-10:],
            "average_gap": avg_gap,
            "overdue_threshold": avg_gap * 1.5,
        }

    def _analyze_positional(self, lottery_id, draws):
        """Which numbers tend to appear in which position (1st, 2nd, etc.)."""
        cfg = LOTTERIES[lottery_id]
        pos_counts = defaultdict(Counter)

        for draw in draws:
            nums = sorted(draw["numbers"])
            for pos, num in enumerate(nums):
                pos_counts[pos][num] += 1

        self.positional_db[lottery_id] = pos_counts
        result = {}
        for pos in range(cfg["numbers_picked"]):
            top = pos_counts[pos].most_common(10)
            result[f"position_{pos + 1}"] = [{"number": n, "count": c} for n, c in top]
        return result

    def _analyze_consecutives(self, lottery_id, draws):
        """Track how often consecutive numbers appear together."""
        patterns = []
        for draw in draws:
            nums = sorted(draw["numbers"])
            runs = []
            current_run = [nums[0]]
            for i in range(1, len(nums)):
                if nums[i] == nums[i - 1] + 1:
                    current_run.append(nums[i])
                else:
                    if len(current_run) >= 2:
                        runs.append(current_run[:])
                    current_run = [nums[i]]
            if len(current_run) >= 2:
                runs.append(current_run[:])
            patterns.append(runs)

        self.consecutive_db[lottery_id] = patterns
        all_runs = [r for p in patterns for r in p]
        run_lengths = Counter(len(r) for r in all_runs)

        return {
            "draws_with_consecutives": sum(1 for p in patterns if p) / max(len(patterns), 1),
            "run_length_distribution": dict(run_lengths),
            "avg_runs_per_draw": np.mean([len(p) for p in patterns]),
        }

    def _analyze_sums(self, lottery_id, draws):
        """Analyze the sum of drawn numbers."""
        sums = [sum(d["numbers"]) for d in draws]
        self.sum_db[lottery_id] = sums
        return {
            "mean_sum": np.mean(sums),
            "std_sum": np.std(sums),
            "min_sum": min(sums),
            "max_sum": max(sums),
            "median_sum": np.median(sums),
            "optimal_range": (np.percentile(sums, 25), np.percentile(sums, 75)),
        }

    def _analyze_transitions(self, lottery_id, draws):
        """Build a transition matrix: P(number_j in draw_t | number_i in draw_t-1)."""
        cfg = LOTTERIES[lottery_id]
        lo, hi = cfg["number_range"]
        trans = defaultdict(Counter)
        total_from = Counter()

        for i in range(len(draws) - 1):
            current = draws[i]["numbers"]
            prior = draws[i + 1]["numbers"]
            for p in prior:
                total_from[p] += 1
                for c in current:
                    trans[p][c] += 1

        # Normalize to probabilities
        matrix = {}
        for p in range(lo, hi + 1):
            if total_from[p] > 0:
                matrix[p] = {c: count / total_from[p] for c, count in trans[p].most_common(10)}

        self.transition_matrix[lottery_id] = matrix
        return {"top_transitions_sample": dict(list(matrix.items())[:5])}

    def _analyze_hot_cold(self, lottery_id, draws):
        """Categorize numbers as hot, warm, or cold based on recent frequency."""
        recent_10 = draws[:10]
        recent_30 = draws[:30]

        freq_10 = Counter()
        freq_30 = Counter()
        for d in recent_10:
            freq_10.update(d["numbers"])
        for d in recent_30:
            freq_30.update(d["numbers"])

        cfg = LOTTERIES[lottery_id]
        lo, hi = cfg["number_range"]

        hot = []
        warm = []
        cold = []
        for n in range(lo, hi + 1):
            f10 = freq_10.get(n, 0)
            f30 = freq_30.get(n, 0)
            if f10 >= 3:
                hot.append(n)
            elif f30 >= 5:
                warm.append(n)
            elif f30 <= 1:
                cold.append(n)

        return {"hot": hot, "warm": warm, "cold": cold}

    def _analyze_day_before(self, lottery_id, draws):
        """
        THE DAY BEFORE ANALYSIS.
        Look at what happened the day before each draw across ALL lotteries.
        Numbers drawn the day before often echo into the next day's draw.
        """
        day_before_hits = Counter()
        day_before_adjacent_hits = Counter()
        total_checked = 0

        for i, draw in enumerate(draws[:-1]):
            draw_date = draw["date"]
            # Look at the next draw in sequence (which is the prior date)
            prior = draws[i + 1]
            current_nums = set(draw["numbers"])
            prior_nums = set(prior["numbers"])

            # Direct matches
            matches = current_nums & prior_nums
            for m in matches:
                day_before_hits[m] += 1
            total_checked += 1

            # Adjacent matches (+/- 1)
            for c in current_nums:
                for p in prior_nums:
                    if abs(c - p) == 1:
                        day_before_adjacent_hits[(p, c)] += 1

        return {
            "direct_repeat_rate": sum(day_before_hits.values()) / max(total_checked, 1),
            "top_repeating_numbers": day_before_hits.most_common(15),
            "adjacent_transfer_rate": sum(day_before_adjacent_hits.values()) / max(total_checked, 1),
            "top_adjacent_transfers": day_before_adjacent_hits.most_common(15),
        }

    def _analyze_alternating_future_links(self, lottery_id, draws):
        """
        THE CORE STRATEGY: Every 2nd draw has a number that appears in future draws.
        Validate this pattern and find the linking numbers.
        """
        interval = STRATEGY["alternating_interval"]
        link_hits = 0
        total_checks = 0
        linking_numbers = Counter()

        for i in range(0, len(draws) - interval - 2, interval):
            source_draw = draws[i]
            # Check if any number from source appears in draws[i+2]
            future_draw = draws[i + interval] if i + interval < len(draws) else None
            if not future_draw:
                break

            source_nums = set(source_draw["numbers"])
            future_nums = set(future_draw["numbers"])

            shared = source_nums & future_nums
            total_checks += 1
            if shared:
                link_hits += 1
                for s in shared:
                    linking_numbers[s] += 1

        link_rate = link_hits / max(total_checks, 1)
        return {
            "link_rate": link_rate,
            "total_checks": total_checks,
            "link_hits": link_hits,
            "pattern_strength": "STRONG" if link_rate > 0.5 else "MODERATE" if link_rate > 0.3 else "WEAK",
            "top_linking_numbers": linking_numbers.most_common(15),
        }

    def _analyze_prior_draw_links(self, lottery_id, draws):
        """
        LOTTO 6/49 SPECIAL: Every draw has at least 1 number from the prior draw
        or adjacent (+/-1). Validate and quantify.
        """
        hits = 0
        adjacent_hits = 0
        total = 0
        match_details = []

        for i in range(len(draws) - 1):
            current = set(draws[i]["numbers"])
            prior = set(draws[i + 1]["numbers"])
            total += 1

            # Direct match
            direct = current & prior
            if direct:
                hits += 1
                match_details.append({"type": "direct", "numbers": list(direct), "draw_idx": i})
                continue

            # Adjacent match (+/- 1)
            adj_found = []
            for c in current:
                for p in prior:
                    if abs(c - p) == 1:
                        adj_found.append({"current": c, "prior": p})
            if adj_found:
                adjacent_hits += 1
                hits += 1
                match_details.append({"type": "adjacent", "links": adj_found, "draw_idx": i})

        total_rate = hits / max(total, 1)
        return {
            "total_link_rate": total_rate,
            "direct_match_rate": (hits - adjacent_hits) / max(total, 1),
            "adjacent_match_rate": adjacent_hits / max(total, 1),
            "pattern_confirmed": total_rate > 0.7,
            "recent_matches": match_details[:10],
        }

    def get_prediction_inputs(self, lottery_id, draws):
        """
        Compile all pattern data into a prediction-ready format.
        Every signal matters. Every number tells a story.
        """
        analysis = self.analyze(lottery_id, draws)
        cfg = LOTTERIES[lottery_id]

        hot_numbers = set(analysis["hot_cold"]["hot"])
        warm_numbers = set(analysis["hot_cold"]["warm"])
        cold_numbers = set(analysis["hot_cold"]["cold"])

        # Overdue numbers that might be "due"
        overdue = [n for n, g in analysis["gaps"]["most_overdue"][:10]]

        # Top pairs
        top_pairs = [p["pair"] for p in analysis["pairs"]["top_pairs"][:15]]

        # Top triplets
        top_triplets = [t["triplet"] for t in analysis["triplets"]["top_triplets"][:10]]

        # Linking numbers from alternating pattern
        alt_links = [n for n, _ in analysis["alternating_links"]["top_linking_numbers"][:10]]

        # Prior draw numbers (for 649 rule)
        prior_nums = draws[0]["numbers"] if draws else []
        prior_adjacents = set()
        for n in prior_nums:
            prior_adjacents.add(max(cfg["number_range"][0], n - 1))
            prior_adjacents.add(n)
            prior_adjacents.add(min(cfg["number_range"][1], n + 1))

        # Sum range
        optimal_sum = analysis["sums"]["optimal_range"]

        return {
            "analysis": analysis,
            "hot": hot_numbers,
            "warm": warm_numbers,
            "cold": cold_numbers,
            "overdue": overdue,
            "top_pairs": top_pairs,
            "top_triplets": top_triplets,
            "alternating_links": alt_links,
            "prior_draw_numbers": prior_nums,
            "prior_adjacents": prior_adjacents,
            "optimal_sum_range": optimal_sum,
            "day_before_repeat_rate": analysis["day_before_patterns"]["direct_repeat_rate"],
        }
