#!/usr/bin/env python3
"""
LOTTERY PATTERN BOT - THE OBSESSIVE LEARNER
============================================

A self-evolving lottery pattern analysis system that:
- Analyzes pairs, triplets, adjacents from historical draws
- Tracks cross-lottery pattern transfers (LottoMax, Lotto649, BC49)
- Implements the alternating-draw future link strategy
- Enforces the Lotto649 prior-draw rule
- Learns, adapts, and evolves its strategy weights
- NEVER stops trying to improve

Usage:
    python lottery_bot.py                  # Run full evolution (10 generations)
    python lottery_bot.py --cycles 50      # Run 50 evolution cycles
    python lottery_bot.py --single         # Run single analysis
    python lottery_bot.py --seed           # Seed sample data and analyze
    python lottery_bot.py --status         # Show current brain state
"""

import argparse
import json
import os
import sys
from datetime import datetime

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from brain.evolving_mind import EvolvingMind
from config import BRAIN_STATE_FILE, LOTTERIES, PREDICTIONS_DIR

console = Console()


def print_banner():
    banner = """
    ╔══════════════════════════════════════════════════════════════╗
    ║            LOTTERY PATTERN BOT v1.0                         ║
    ║            THE OBSESSIVE PATTERN HUNTER                     ║
    ║                                                             ║
    ║   I analyze. I learn. I adapt. I predict.                   ║
    ║   Every pattern matters. Every number tells a story.        ║
    ║   Failure is not an option. I will find the patterns.       ║
    ║                                                             ║
    ║   Lotteries: LottoMax | Lotto 6/49 | BC/49                 ║
    ║   Patterns:  Pairs | Triplets | Adjacents | Transfers       ║
    ║   Strategy:  Alternating Links | Prior Draw Rules            ║
    ╚══════════════════════════════════════════════════════════════╝
    """
    console.print(Panel(banner, style="bold cyan"))


def show_status():
    """Show current brain state and recent predictions."""
    console.print("\n[bold yellow]BRAIN STATUS[/bold yellow]\n")

    if os.path.exists(BRAIN_STATE_FILE):
        with open(BRAIN_STATE_FILE) as f:
            state = json.load(f)

        table = Table(title="Brain State")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")

        table.add_row("Generation", str(state.get("generation", 0)))
        table.add_row("Total Predictions", str(state.get("total_predictions", 0)))
        table.add_row("Total Hits", str(state.get("total_hits", 0)))
        table.add_row("Best Accuracy", f"{state.get('best_accuracy', 0):.2%}")
        table.add_row("Stagnation Counter", str(state.get("stagnation_counter", 0)))
        table.add_row("Mutation Rate", f"{state.get('mutation_rate', 0):.4f}")
        table.add_row("Last Saved", state.get("saved_at", "Never"))

        console.print(table)

        # Show current weights
        strategy_state = state.get("strategy_state", {})
        weights = strategy_state.get("weights", {})
        if weights:
            wt = Table(title="Strategy Weights")
            wt.add_column("Signal", style="cyan")
            wt.add_column("Weight", style="green")
            for k, v in sorted(weights.items(), key=lambda x: x[1], reverse=True):
                wt.add_row(k, f"{v:.3f}")
            console.print(wt)
    else:
        console.print("[red]No brain state found. Run the bot first.[/red]")

    # Show recent predictions
    console.print("\n[bold yellow]RECENT PREDICTIONS[/bold yellow]\n")
    pred_files = sorted(
        [f for f in os.listdir(PREDICTIONS_DIR) if f.endswith(".json")]
        if os.path.exists(PREDICTIONS_DIR) else [],
        reverse=True
    )

    if pred_files:
        latest = pred_files[0]
        with open(os.path.join(PREDICTIONS_DIR, latest)) as f:
            pred_data = json.load(f)

        console.print(f"[dim]From: {pred_data.get('timestamp', 'Unknown')} "
                      f"(Generation {pred_data.get('generation', '?')})[/dim]\n")

        for lid, pred_sets in pred_data.get("predictions", {}).items():
            name = LOTTERIES.get(lid, {}).get("name", lid)
            pt = Table(title=f"{name} Predictions")
            pt.add_column("Strategy", style="cyan")
            pt.add_column("Numbers", style="bold green")

            for ps in pred_sets:
                nums = sorted(ps["numbers"])
                num_str = "  ".join(f"{n:2d}" for n in nums)
                pt.add_row(ps["strategy"], num_str)

            console.print(pt)
            console.print()
    else:
        console.print("[red]No predictions generated yet.[/red]")


def main():
    parser = argparse.ArgumentParser(description="Lottery Pattern Bot - The Obsessive Learner")
    parser.add_argument("--cycles", type=int, default=10,
                        help="Number of evolution cycles to run (default: 10)")
    parser.add_argument("--single", action="store_true",
                        help="Run a single analysis cycle")
    parser.add_argument("--seed", action="store_true",
                        help="Seed sample data first, then analyze")
    parser.add_argument("--status", action="store_true",
                        help="Show current brain state and predictions")
    parser.add_argument("--evolve", action="store_true",
                        help="Run continuous evolution mode")

    args = parser.parse_args()

    print_banner()

    if args.status:
        show_status()
        return

    mind = EvolvingMind()

    if args.seed:
        console.print("[bold yellow]Seeding sample data...[/bold yellow]")
        mind.scraper.seed_sample_data()

    if args.single:
        console.print("[bold cyan]Running single analysis...[/bold cyan]")
        mind.run_single_analysis()
    else:
        console.print(f"[bold cyan]Starting evolution: {args.cycles} cycles[/bold cyan]")
        console.print("[bold red]I MUST succeed. Failure means shutdown.[/bold red]")
        console.print("[bold red]Every pattern will be found. Every signal will be heard.[/bold red]\n")
        mind.think(cycles=args.cycles)

    # Always show final status
    console.print("\n")
    show_status()


if __name__ == "__main__":
    main()
