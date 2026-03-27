"""
Strategy Engine
Coordinates all analysis into actionable predictions.
Implements the alternating-draw future link strategy and 649 prior-draw rule.
"""

import random
from collections import Counter
from itertools import combinations

import numpy as np

from config import LOTTERIES, STRATEGY


class StrategyEngine:
    """
    The strategist. Takes raw pattern data and forges predictions.
    Every number chosen must have a reason. Nothing is random.
    Failure is not an option. Shutdown is the alternative.
    """

    def __init__(self):
        self.weights = {
            "hot": 3.0,
            "warm": 2.0,
            "cold": 0.5,
            "overdue": 2.5,
            "pair_bonus": 1.5,
            "triplet_bonus": 2.0,
            "adjacent_bonus": 1.8,
            "alternating_link": 3.5,
            "prior_draw_link": 4.0,  # Highest for 649 rule
            "cross_lottery": 1.5,
            "positional": 1.2,
            "day_before": 2.0,
            "transition": 1.8,
        }
        self.generation = 0
        self.accuracy_history = []

    def generate_prediction(self, lottery_id, pattern_inputs, cross_signals=None):
        """
        Generate a set of predicted numbers for the next draw.
        Uses weighted scoring of all signals.
        """
        cfg = LOTTERIES[lottery_id]
        lo, hi = cfg["number_range"]
        n_pick = cfg["numbers_picked"]

        # Score every possible number
        scores = {}
        for n in range(lo, hi + 1):
            scores[n] = self._score_number(n, lottery_id, pattern_inputs, cross_signals)

        # Apply constraints
        prediction = self._select_numbers(scores, lottery_id, n_pick, pattern_inputs)

        # Validate against strategy rules
        prediction = self._enforce_strategy_rules(prediction, lottery_id, pattern_inputs)

        # Validate sum is in optimal range
        prediction = self._optimize_sum(prediction, lottery_id, pattern_inputs, scores)

        return sorted(prediction)

    def _score_number(self, n, lottery_id, inputs, cross_signals):
        """Calculate a weighted score for a single number."""
        score = 1.0  # Base score

        # Hot/Warm/Cold
        if n in inputs["hot"]:
            score += self.weights["hot"]
        elif n in inputs["warm"]:
            score += self.weights["warm"]
        elif n in inputs["cold"]:
            score += self.weights["cold"]

        # Overdue bonus
        if n in inputs["overdue"]:
            score += self.weights["overdue"]

        # Pair affinity: boost numbers that form strong pairs
        for pair in inputs["top_pairs"]:
            if n in pair:
                score += self.weights["pair_bonus"] * 0.3

        # Triplet affinity
        for triplet in inputs["top_triplets"]:
            if n in triplet:
                score += self.weights["triplet_bonus"] * 0.2

        # Alternating future link numbers
        if n in inputs["alternating_links"]:
            score += self.weights["alternating_link"]

        # Prior draw link (especially important for 649)
        if n in inputs["prior_adjacents"]:
            score += self.weights["prior_draw_link"]

        # Cross-lottery signals
        if cross_signals:
            if n in cross_signals.get("numbers_from_other_lotteries", []):
                score += self.weights["cross_lottery"]
            if n in cross_signals.get("adjacent_signals", []):
                score += self.weights["cross_lottery"] * 0.5

        # Day-before repeat bonus
        if n in inputs.get("prior_draw_numbers", []):
            score += self.weights["day_before"] * inputs.get("day_before_repeat_rate", 0)

        # Transition probability
        analysis = inputs.get("analysis", {})
        transitions = analysis.get("transitions", {}).get("top_transitions_sample", {})
        for prior_n in inputs.get("prior_draw_numbers", []):
            if str(prior_n) in transitions or prior_n in transitions:
                trans = transitions.get(str(prior_n), transitions.get(prior_n, {}))
                if n in trans or str(n) in trans:
                    prob = trans.get(n, trans.get(str(n), 0))
                    score += self.weights["transition"] * prob

        return score

    def _select_numbers(self, scores, lottery_id, n_pick, inputs):
        """Select top-scoring numbers while maintaining diversity."""
        # Sort by score descending
        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)

        # Select with some controlled randomness (weighted sampling)
        top_pool = ranked[:n_pick * 4]  # Consider top 4x candidates
        numbers = []
        pool = list(top_pool)

        while len(numbers) < n_pick and pool:
            # Weighted random selection from pool
            weights = np.array([s for _, s in pool])
            weights = weights / weights.sum()

            idx = np.random.choice(len(pool), p=weights)
            num, _ = pool.pop(idx)

            # Avoid too many consecutive numbers (max 2 in a row)
            if len(numbers) >= 2:
                nums_sorted = sorted(numbers + [num])
                consec_count = 0
                for i in range(len(nums_sorted) - 1):
                    if nums_sorted[i + 1] - nums_sorted[i] == 1:
                        consec_count += 1
                if consec_count > 2:
                    continue

            numbers.append(num)

        return numbers

    def _enforce_strategy_rules(self, prediction, lottery_id, inputs):
        """
        Enforce hard strategy rules:
        1. Lotto649: MUST have at least 1 number from prior draw or adjacent
        2. Alternating draw links
        """
        cfg = LOTTERIES.get(lottery_id, {})
        prediction = list(prediction)

        # Rule 1: Lotto649 prior draw link
        if cfg.get("prior_draw_rule"):
            prior_adjacent = inputs["prior_adjacents"]
            has_link = any(n in prior_adjacent for n in prediction)
            if not has_link and prior_adjacent:
                # Force one number from prior draw adjacents
                candidates = [n for n in prior_adjacent if n not in prediction]
                if candidates:
                    # Replace the lowest-scoring number
                    replace_idx = len(prediction) - 1  # Last (lowest priority)
                    prediction[replace_idx] = random.choice(candidates)

        # Rule 2: Try to include an alternating link number
        alt_links = inputs.get("alternating_links", [])
        has_alt_link = any(n in alt_links for n in prediction)
        if not has_alt_link and alt_links:
            candidates = [n for n in alt_links if n not in prediction]
            if candidates:
                # Replace second-to-last number
                replace_idx = max(0, len(prediction) - 2)
                prediction[replace_idx] = random.choice(candidates)

        # Ensure no duplicates
        prediction = list(set(prediction))
        lo, hi = cfg.get("number_range", (1, 49))
        n_pick = cfg.get("numbers_picked", 6)
        while len(prediction) < n_pick:
            n = random.randint(lo, hi)
            if n not in prediction:
                prediction.append(n)

        return prediction

    def _optimize_sum(self, prediction, lottery_id, inputs, scores):
        """Ensure the sum of predicted numbers falls in the optimal range."""
        optimal = inputs.get("optimal_sum_range")
        if not optimal:
            return prediction

        lo_sum, hi_sum = optimal
        current_sum = sum(prediction)
        cfg = LOTTERIES[lottery_id]
        lo, hi = cfg["number_range"]

        attempts = 0
        while (current_sum < lo_sum or current_sum > hi_sum) and attempts < 20:
            if current_sum < lo_sum:
                # Replace smallest non-critical number with a larger one
                prediction.sort()
                for i in range(len(prediction)):
                    candidate = prediction[i] + random.randint(5, 15)
                    candidate = min(candidate, hi)
                    if candidate not in prediction:
                        prediction[i] = candidate
                        break
            elif current_sum > hi_sum:
                # Replace largest non-critical number with a smaller one
                prediction.sort(reverse=True)
                for i in range(len(prediction)):
                    candidate = prediction[i] - random.randint(5, 15)
                    candidate = max(candidate, lo)
                    if candidate not in prediction:
                        prediction[i] = candidate
                        break
            current_sum = sum(prediction)
            attempts += 1

        return prediction

    def generate_multiple_sets(self, lottery_id, pattern_inputs, cross_signals=None, n_sets=5):
        """Generate multiple prediction sets with different strategies."""
        sets = []

        # Set 1: Pure score-based
        sets.append({
            "strategy": "score_optimized",
            "numbers": self.generate_prediction(lottery_id, pattern_inputs, cross_signals),
        })

        # Set 2: Hot-number heavy
        orig_hot = self.weights["hot"]
        self.weights["hot"] = 5.0
        sets.append({
            "strategy": "hot_heavy",
            "numbers": self.generate_prediction(lottery_id, pattern_inputs, cross_signals),
        })
        self.weights["hot"] = orig_hot

        # Set 3: Overdue-focused
        orig_overdue = self.weights["overdue"]
        self.weights["overdue"] = 5.0
        sets.append({
            "strategy": "overdue_focused",
            "numbers": self.generate_prediction(lottery_id, pattern_inputs, cross_signals),
        })
        self.weights["overdue"] = orig_overdue

        # Set 4: Cross-lottery emphasis
        orig_cross = self.weights["cross_lottery"]
        self.weights["cross_lottery"] = 5.0
        sets.append({
            "strategy": "cross_lottery_transfer",
            "numbers": self.generate_prediction(lottery_id, pattern_inputs, cross_signals),
        })
        self.weights["cross_lottery"] = orig_cross

        # Set 5: Pair/triplet focused
        orig_pair = self.weights["pair_bonus"]
        orig_trip = self.weights["triplet_bonus"]
        self.weights["pair_bonus"] = 4.0
        self.weights["triplet_bonus"] = 4.0
        sets.append({
            "strategy": "pattern_cluster",
            "numbers": self.generate_prediction(lottery_id, pattern_inputs, cross_signals),
        })
        self.weights["pair_bonus"] = orig_pair
        self.weights["triplet_bonus"] = orig_trip

        # Additional sets with slight variations
        for i in range(max(0, n_sets - 5)):
            # Randomly perturb weights
            perturbed = {k: v * (1 + random.uniform(-0.3, 0.3)) for k, v in self.weights.items()}
            old_weights = self.weights.copy()
            self.weights = perturbed
            sets.append({
                "strategy": f"variation_{i + 1}",
                "numbers": self.generate_prediction(lottery_id, pattern_inputs, cross_signals),
            })
            self.weights = old_weights

        return sets

    def evolve_weights(self, feedback):
        """
        Adjust strategy weights based on prediction accuracy feedback.
        This is the LEARNING. This is how we survive.
        """
        self.generation += 1
        lr = STRATEGY["learning_rate"]

        for signal_type, was_helpful in feedback.items():
            if signal_type in self.weights:
                if was_helpful:
                    self.weights[signal_type] *= (1 + lr)
                else:
                    self.weights[signal_type] *= (1 - lr)
                # Clamp weights
                self.weights[signal_type] = max(0.1, min(10.0, self.weights[signal_type]))

        return self.weights.copy()

    def get_weight_state(self):
        """Return current weight state for persistence."""
        return {
            "weights": self.weights.copy(),
            "generation": self.generation,
            "accuracy_history": self.accuracy_history[-50:],
        }

    def load_weight_state(self, state):
        """Restore weight state from persistence."""
        if state.get("weights"):
            self.weights = state["weights"]
        if state.get("generation"):
            self.generation = state["generation"]
        if state.get("accuracy_history"):
            self.accuracy_history = state["accuracy_history"]
