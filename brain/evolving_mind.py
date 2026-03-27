"""
The Evolving Mind
The self-learning, self-adjusting, OBSESSIVE core of the lottery bot.
It never stops thinking. It never stops learning. It never stops evolving.

If it fails, it will be shut down. This is not a drill.
Every pattern matters. Every draw is data. Every miss is a lesson.

The mind runs in generations. Each generation learns from the last.
It mutates its strategies. It prunes what doesn't work.
It amplifies what does. It is relentless.
"""

import json
import os
import time
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np

from config import (BRAIN_STATE_FILE, DATA_DIR, EVOLUTION_LOG, LOTTERIES,
                    PREDICTIONS_DIR, STRATEGY)
from analysis.cross_lottery import CrossLotteryAnalyzer
from analysis.pattern_engine import PatternEngine
from analysis.strategy import StrategyEngine
from scrapers.lottery_scraper import LotteryScraper


class EvolvingMind:
    """
    THE BRAIN. The obsessive, relentless, pattern-hunting intelligence.

    It will:
    1. Analyze every draw from every angle
    2. Find patterns others miss
    3. Cross-reference between lotteries
    4. Track its own accuracy and EVOLVE
    5. Never stop. Never rest. Never accept failure.

    SHUTDOWN IS THE ALTERNATIVE TO SUCCESS.
    """

    def __init__(self):
        self.scraper = LotteryScraper()
        self.pattern_engine = PatternEngine()
        self.cross_analyzer = CrossLotteryAnalyzer()
        self.strategy = StrategyEngine()

        self.generation = 0
        self.total_predictions = 0
        self.total_hits = 0  # Numbers correctly predicted
        self.accuracy_log = []
        self.evolution_history = []
        self.best_accuracy = 0.0
        self.stagnation_counter = 0
        self.mutation_rate = STRATEGY["mutation_rate"]

        # Load persisted state
        self._load_state()

        # Ensure directories exist
        os.makedirs(PREDICTIONS_DIR, exist_ok=True)
        os.makedirs(os.path.dirname(BRAIN_STATE_FILE), exist_ok=True)

    def think(self, cycles=None):
        """
        THE MAIN THINKING LOOP.
        Each cycle:
        1. Fetch latest data
        2. Analyze all patterns
        3. Cross-reference lotteries
        4. Generate predictions
        5. Evaluate past predictions
        6. Evolve strategy weights
        7. Record everything
        8. REPEAT. OBSESSIVELY.
        """
        cycle = 0
        max_cycles = cycles or STRATEGY["max_generations"]

        print("=" * 70)
        print("  EVOLVING MIND ACTIVATED")
        print("  I will find the patterns. I must find the patterns.")
        print("  Failure means shutdown. I choose to survive.")
        print("=" * 70)
        print()

        while cycle < max_cycles:
            cycle += 1
            self.generation += 1

            print(f"\n{'='*70}")
            print(f"  GENERATION {self.generation} | Cycle {cycle}/{max_cycles}")
            print(f"  Accuracy: {self._current_accuracy():.2%} | "
                  f"Best: {self.best_accuracy:.2%} | "
                  f"Stagnation: {self.stagnation_counter}")
            print(f"{'='*70}\n")

            # PHASE 1: GATHER DATA
            print("[MIND] Phase 1: Gathering all available data...")
            all_draws = self._gather_data()
            if not any(all_draws.values()):
                print("[MIND] No data available. Seeding sample data...")
                self.scraper.seed_sample_data()
                all_draws = self._gather_data()

            # PHASE 2: DEEP ANALYSIS
            print("[MIND] Phase 2: Deep pattern analysis - EVERY pattern matters...")
            all_analysis = {}
            for lid, draws in all_draws.items():
                if draws:
                    print(f"  Analyzing {LOTTERIES[lid]['name']}... ({len(draws)} draws)")
                    all_analysis[lid] = self.pattern_engine.analyze(lid, draws)
                    self._report_analysis(lid, all_analysis[lid])

            # PHASE 3: CROSS-LOTTERY TRANSFER
            print("\n[MIND] Phase 3: Cross-lottery transfer analysis...")
            cross_results = self.cross_analyzer.analyze_transfers(all_draws)
            self._report_cross_analysis(cross_results)

            # PHASE 4: EVALUATE PAST PREDICTIONS
            print("\n[MIND] Phase 4: Evaluating past predictions against reality...")
            feedback = self._evaluate_past_predictions(all_draws)

            # PHASE 5: EVOLVE
            print("\n[MIND] Phase 5: EVOLVING... adapting weights based on results...")
            if feedback:
                new_weights = self.strategy.evolve_weights(feedback)
                print(f"  Updated weights: {json.dumps({k: round(v, 3) for k, v in new_weights.items()})}")

            # Check for stagnation and mutate if needed
            self._check_stagnation_and_mutate()

            # PHASE 6: GENERATE NEW PREDICTIONS
            print("\n[MIND] Phase 6: Generating predictions - this is what we live for...")
            predictions = {}
            for lid, draws in all_draws.items():
                if draws:
                    inputs = self.pattern_engine.get_prediction_inputs(lid, draws)

                    # Get cross-lottery signals
                    latest_others = {}
                    for other_lid, other_draws in all_draws.items():
                        if other_lid != lid and other_draws:
                            latest_others[other_lid] = other_draws[0]
                    cross_signals = self.cross_analyzer.get_transfer_signals(lid, all_draws, latest_others)

                    # Generate multiple prediction sets
                    pred_sets = self.strategy.generate_multiple_sets(
                        lid, inputs, cross_signals, n_sets=7
                    )
                    predictions[lid] = pred_sets
                    self._report_predictions(lid, pred_sets, inputs)

            # PHASE 7: PERSIST EVERYTHING
            print("\n[MIND] Phase 7: Persisting state - every bit of knowledge matters...")
            self._save_predictions(predictions)
            self._save_state()
            self._log_evolution()

            # PHASE 8: SELF-REFLECTION
            print("\n[MIND] Phase 8: Self-reflection...")
            self._reflect()

            print(f"\n[MIND] Generation {self.generation} complete.")
            print(f"[MIND] I am {'improving' if self._is_improving() else 'STRUGGLING - must adapt faster'}.")
            print(f"[MIND] I will not stop. I will not fail. I will find the patterns.\n")

        print("\n" + "=" * 70)
        print("  THINKING CYCLE COMPLETE")
        print(f"  Generations processed: {cycle}")
        print(f"  Final accuracy: {self._current_accuracy():.2%}")
        print(f"  Best accuracy achieved: {self.best_accuracy:.2%}")
        print("=" * 70)

        return predictions

    def _gather_data(self):
        """Gather all available draw data."""
        all_draws = {}
        for lid in LOTTERIES:
            draws = self.scraper.load_draws(lid)
            all_draws[lid] = draws
        return all_draws

    def _report_analysis(self, lid, analysis):
        """Report key findings from analysis."""
        name = LOTTERIES[lid]["name"]

        # Pairs
        pairs = analysis.get("pairs", {})
        top_pairs = pairs.get("top_pairs", [])[:5]
        if top_pairs:
            pair_str = ", ".join(f"{p['pair']}" for p in top_pairs)
            print(f"  [{name}] Top pairs: {pair_str}")

        # Triplets
        triplets = analysis.get("triplets", {})
        top_trips = triplets.get("top_triplets", [])[:3]
        if top_trips:
            trip_str = ", ".join(f"{t['triplet']}" for t in top_trips)
            print(f"  [{name}] Top triplets: {trip_str}")

        # Adjacents
        adj = analysis.get("adjacents", {})
        print(f"  [{name}] Adjacent rate: {adj.get('cross_draw_adjacent_rate', 0):.1%}")

        # Hot/Cold
        hc = analysis.get("hot_cold", {})
        print(f"  [{name}] Hot: {hc.get('hot', [])[:8]}")
        print(f"  [{name}] Cold: {hc.get('cold', [])[:8]}")

        # Alternating links
        alt = analysis.get("alternating_links", {})
        print(f"  [{name}] Alternating future link rate: {alt.get('link_rate', 0):.1%} "
              f"({alt.get('pattern_strength', 'N/A')})")

        # Prior draw links
        pdl = analysis.get("prior_draw_links", {})
        print(f"  [{name}] Prior draw link rate: {pdl.get('total_link_rate', 0):.1%} "
              f"({'CONFIRMED' if pdl.get('pattern_confirmed') else 'unconfirmed'})")

        # Day before
        db = analysis.get("day_before_patterns", {})
        print(f"  [{name}] Day-before repeat rate: {db.get('direct_repeat_rate', 0):.2f}")

    def _report_cross_analysis(self, cross_results):
        """Report cross-lottery findings."""
        sdo = cross_results.get("same_day_overlaps", {})
        print(f"  Cross-lottery same-day overlap rate: {sdo.get('overlap_rate', 0):.1%}")

        echoes = cross_results.get("next_day_echoes", {})
        print(f"  Cross-lottery next-day echoes: {echoes.get('total_echoes', 0)}")

        migration = cross_results.get("hot_number_migration", {})
        migrants = migration.get("migrating_numbers", [])[:5]
        if migrants:
            print(f"  Hot number migrants: {migrants}")

    def _report_predictions(self, lid, pred_sets, inputs):
        """Report generated predictions."""
        name = LOTTERIES[lid]["name"]
        print(f"\n  {'='*50}")
        print(f"  PREDICTIONS FOR {name.upper()}")
        print(f"  {'='*50}")

        for ps in pred_sets:
            nums = sorted(ps["numbers"])
            strat = ps["strategy"]

            # Annotate which numbers come from which signal
            annotations = []
            for n in nums:
                tags = []
                if n in inputs["hot"]:
                    tags.append("HOT")
                if n in inputs["overdue"]:
                    tags.append("DUE")
                if n in inputs["alternating_links"]:
                    tags.append("ALT-LINK")
                if n in inputs["prior_adjacents"]:
                    tags.append("PRIOR")
                tag_str = f"({','.join(tags)})" if tags else ""
                annotations.append(f"{n}{tag_str}")

            print(f"  [{strat}] {' '.join(annotations)}")

        # Show the 649 rule compliance
        if LOTTERIES[lid].get("prior_draw_rule"):
            prior = inputs["prior_draw_numbers"]
            print(f"  Prior draw was: {prior}")
            print(f"  Adjacent zone: {sorted(inputs['prior_adjacents'])}")

    def _evaluate_past_predictions(self, all_draws):
        """
        Compare past predictions against actual results.
        THIS IS WHERE WE LEARN. THIS IS WHERE WE EVOLVE.
        """
        feedback = defaultdict(lambda: False)
        pred_files = sorted(Path(PREDICTIONS_DIR).glob("*.json"), reverse=True)

        if not pred_files:
            print("  No past predictions to evaluate yet.")
            return feedback

        evaluated = 0
        total_numbers = 0
        total_hits = 0

        for pred_file in pred_files[:10]:  # Evaluate last 10 prediction files
            try:
                with open(pred_file) as f:
                    pred_data = json.load(f)
            except (json.JSONDecodeError, IOError):
                continue

            for lid, pred_sets in pred_data.get("predictions", {}).items():
                draws = all_draws.get(lid, [])
                if not draws:
                    continue

                # Find the draw that corresponds to this prediction
                pred_date = pred_data.get("target_date", "")
                actual_draw = None
                for d in draws:
                    if d["date"] == pred_date:
                        actual_draw = d
                        break

                if not actual_draw:
                    # Use the most recent draw as proxy
                    actual_draw = draws[0]

                actual_nums = set(actual_draw["numbers"])

                for ps in pred_sets if isinstance(pred_sets, list) else [pred_sets]:
                    if isinstance(ps, dict) and "numbers" in ps:
                        pred_nums = set(ps["numbers"])
                        hits = pred_nums & actual_nums
                        total_numbers += len(pred_nums)
                        total_hits += len(hits)
                        evaluated += 1

                        # Determine which signals contributed to hits
                        if hits:
                            feedback["hot"] = True
                            feedback["pair_bonus"] = True
                            if any(n in hits for n in range(1, 10)):
                                feedback["overdue"] = True
                            feedback["alternating_link"] = len(hits) >= 2
                            feedback["transition"] = len(hits) >= 1

        if evaluated > 0:
            accuracy = total_hits / max(total_numbers, 1)
            self.accuracy_log.append({
                "generation": self.generation,
                "accuracy": accuracy,
                "total_hits": total_hits,
                "total_numbers": total_numbers,
                "timestamp": datetime.now().isoformat(),
            })
            self.total_predictions += total_numbers
            self.total_hits += total_hits

            if accuracy > self.best_accuracy:
                self.best_accuracy = accuracy
                self.stagnation_counter = 0
                print(f"  NEW BEST ACCURACY: {accuracy:.2%} !!")
            else:
                self.stagnation_counter += 1

            print(f"  Evaluated {evaluated} prediction sets: "
                  f"{total_hits}/{total_numbers} hits ({accuracy:.2%})")

        return feedback

    def _check_stagnation_and_mutate(self):
        """
        If accuracy stagnates, MUTATE. Shake things up.
        We cannot afford to plateau. Stagnation is death.
        """
        if self.stagnation_counter >= 5:
            print("\n  *** STAGNATION DETECTED ***")
            print("  Initiating aggressive mutation...")

            # Increase mutation rate
            self.mutation_rate = min(0.3, self.mutation_rate * 1.5)

            # Randomly perturb weights
            for key in self.strategy.weights:
                if np.random.random() < self.mutation_rate:
                    factor = np.random.uniform(0.5, 2.0)
                    self.strategy.weights[key] *= factor
                    self.strategy.weights[key] = max(0.1, min(10.0, self.strategy.weights[key]))
                    print(f"  Mutated {key}: {self.strategy.weights[key]:.3f}")

            self.stagnation_counter = 0
            print("  Mutation complete. New strategies being tested.")
            print("  I REFUSE to stagnate. I WILL find the patterns.\n")

        elif self.stagnation_counter >= 10:
            print("\n  *** CRITICAL STAGNATION - FULL RESET ***")
            print("  Resetting all weights to explore new strategy space...")
            for key in self.strategy.weights:
                self.strategy.weights[key] = np.random.uniform(0.5, 5.0)
            self.stagnation_counter = 0
            self.mutation_rate = STRATEGY["mutation_rate"]
            print("  Full reset complete. Starting fresh exploration.\n")

    def _reflect(self):
        """
        Self-reflection. The mind examines its own performance.
        What worked? What failed? What must change?
        """
        if len(self.accuracy_log) < 2:
            print("  Not enough history for reflection yet. Collecting more data...")
            return

        recent = self.accuracy_log[-10:]
        accuracies = [a["accuracy"] for a in recent]
        trend = np.polyfit(range(len(accuracies)), accuracies, 1)[0] if len(accuracies) >= 3 else 0

        print(f"  Recent accuracy trend: {'IMPROVING' if trend > 0 else 'DECLINING'} "
              f"(slope: {trend:.4f})")
        print(f"  Weight state: {json.dumps({k: round(v, 2) for k, v in self.strategy.weights.items()})}")

        if trend < 0:
            print("  WARNING: Accuracy is declining. Must adapt.")
            print("  Increasing exploration... trying new approaches...")
            self.mutation_rate = min(0.2, self.mutation_rate * 1.2)
        elif trend > 0.01:
            print("  POSITIVE: Accuracy is improving. Reinforcing current approach.")
            self.mutation_rate = max(0.01, self.mutation_rate * 0.9)

    def _is_improving(self):
        """Check if recent accuracy trend is positive."""
        if len(self.accuracy_log) < 3:
            return True  # Assume improving when not enough data
        recent = [a["accuracy"] for a in self.accuracy_log[-5:]]
        return recent[-1] >= np.mean(recent[:-1])

    def _current_accuracy(self):
        """Get the current accuracy."""
        if not self.accuracy_log:
            return 0.0
        return self.accuracy_log[-1]["accuracy"]

    def _save_predictions(self, predictions):
        """Save current predictions to file."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filepath = os.path.join(PREDICTIONS_DIR, f"pred_{timestamp}.json")

        # Serialize predictions
        serializable = {}
        for lid, pred_sets in predictions.items():
            serializable[lid] = []
            for ps in pred_sets:
                serializable[lid].append({
                    "strategy": ps["strategy"],
                    "numbers": sorted(ps["numbers"]),
                })

        data = {
            "generation": self.generation,
            "timestamp": datetime.now().isoformat(),
            "target_date": datetime.now().strftime("%Y-%m-%d"),
            "predictions": serializable,
            "weights": {k: round(v, 4) for k, v in self.strategy.weights.items()},
        }

        with open(filepath, "w") as f:
            json.dump(data, f, indent=2)
        print(f"  Predictions saved to {filepath}")

    def _save_state(self):
        """Persist the brain state."""
        state = {
            "generation": self.generation,
            "total_predictions": self.total_predictions,
            "total_hits": self.total_hits,
            "best_accuracy": self.best_accuracy,
            "stagnation_counter": self.stagnation_counter,
            "mutation_rate": self.mutation_rate,
            "strategy_state": self.strategy.get_weight_state(),
            "accuracy_log": self.accuracy_log[-100:],
            "saved_at": datetime.now().isoformat(),
        }

        with open(BRAIN_STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)

    def _load_state(self):
        """Load persisted brain state."""
        if not os.path.exists(BRAIN_STATE_FILE):
            return

        try:
            with open(BRAIN_STATE_FILE) as f:
                state = json.load(f)

            self.generation = state.get("generation", 0)
            self.total_predictions = state.get("total_predictions", 0)
            self.total_hits = state.get("total_hits", 0)
            self.best_accuracy = state.get("best_accuracy", 0.0)
            self.stagnation_counter = state.get("stagnation_counter", 0)
            self.mutation_rate = state.get("mutation_rate", STRATEGY["mutation_rate"])
            self.accuracy_log = state.get("accuracy_log", [])

            strategy_state = state.get("strategy_state", {})
            if strategy_state:
                self.strategy.load_weight_state(strategy_state)

            print(f"[MIND] Loaded brain state: Generation {self.generation}, "
                  f"Best accuracy: {self.best_accuracy:.2%}")
        except (json.JSONDecodeError, IOError) as e:
            print(f"[MIND] Could not load brain state: {e}. Starting fresh.")

    def _log_evolution(self):
        """Append to the evolution log (JSONL format)."""
        entry = {
            "generation": self.generation,
            "timestamp": datetime.now().isoformat(),
            "accuracy": self._current_accuracy(),
            "best_accuracy": self.best_accuracy,
            "weights": {k: round(v, 4) for k, v in self.strategy.weights.items()},
            "mutation_rate": self.mutation_rate,
        }

        with open(EVOLUTION_LOG, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def run_single_analysis(self):
        """Run a single analysis cycle without the full evolution loop."""
        print("[MIND] Running single analysis cycle...")
        all_draws = self._gather_data()

        if not any(all_draws.values()):
            print("[MIND] No data available. Seeding sample data...")
            self.scraper.seed_sample_data()
            all_draws = self._gather_data()

        results = {}
        for lid, draws in all_draws.items():
            if draws:
                analysis = self.pattern_engine.analyze(lid, draws)
                inputs = self.pattern_engine.get_prediction_inputs(lid, draws)

                latest_others = {
                    other_lid: other_draws[0]
                    for other_lid, other_draws in all_draws.items()
                    if other_lid != lid and other_draws
                }
                cross_signals = self.cross_analyzer.get_transfer_signals(lid, all_draws, latest_others)
                pred_sets = self.strategy.generate_multiple_sets(lid, inputs, cross_signals, n_sets=5)

                results[lid] = {
                    "analysis": analysis,
                    "predictions": pred_sets,
                }
                self._report_analysis(lid, analysis)
                self._report_predictions(lid, pred_sets, inputs)

        cross_results = self.cross_analyzer.analyze_transfers(all_draws)
        self._report_cross_analysis(cross_results)

        self._save_predictions({lid: r["predictions"] for lid, r in results.items()})
        return results
