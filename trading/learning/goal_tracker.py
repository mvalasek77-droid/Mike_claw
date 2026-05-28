"""Goal-oriented compounding tracker — $180 → $10,000 in 90 trading days.

Tracks progress against the compound growth plan and adjusts
aggression based on whether we're ahead or behind schedule.

Daily compound rate needed: ~4.56% (with 2x leverage = 2.28% WTI daily)
Weekly milestones are set, and position sizing adjusts:
  - On track / ahead → full aggression (98-100% of account)
  - Behind schedule → slightly reduced (85-90%) to preserve capital
  - Way behind → defensive (75%) to avoid blowup
"""
from __future__ import annotations

import json
import math
from datetime import date, datetime, timedelta
from pathlib import Path
from dataclasses import dataclass, field

# ──────────────────────────────────────────────────────────────────────
# The Plan: $180 → $10,000 in 90 trading days
# ──────────────────────────────────────────────────────────────────────

START_CAPITAL = 180.0
TARGET_CAPITAL = 10_000.0
TRADING_DAYS = 90  # 3 months × ~22 trading days/month

# Required daily compound rate
DAILY_RATE = (TARGET_CAPITAL / START_CAPITAL) ** (1 / TRADING_DAYS) - 1  # ~4.56%

# Weekly milestones (5 trading days per week)
def _milestones() -> list[tuple[int, float]]:
    """Generate weekly target milestones."""
    ms = []
    for week in range(1, 14):  # 13 weeks ≈ 3 months
        day = week * 5
        target = START_CAPITAL * ((1 + DAILY_RATE) ** day)
        ms.append((day, round(target)))
    return ms

MILESTONES = _milestones()
WEEK_TARGETS = {i+1: t for i, (d, t) in enumerate(MILESTONES)}


@dataclass
class GoalProgress:
    """Tracks goal progress and adjusts aggression."""
    start_date: date = field(default_factory=date.today)
    current_capital: float = START_CAPITAL
    peak_capital: float = START_CAPITAL
    trade_count: int = 0
    win_count: int = 0
    loss_count: int = 0
    total_pnl: float = 0.0
    best_trade: float = 0.0
    worst_trade: float = 0.0
    consecutive_wins: int = 0
    consecutive_losses: int = 0
    history: list[dict] = field(default_factory=list)  # daily snapshots

    @property
    def day_number(self) -> int:
        """Current trading day (calendar days elapsed, could be smarter)."""
        return max(1, (date.today() - self.start_date).days + 1)

    @property
    def target_today(self) -> float:
        """What our account SHOULD be at today to be on track."""
        return START_CAPITAL * ((1 + DAILY_RATE) ** self.day_number)

    @property
    def ahead_by(self) -> float:
        """Dollar amount we're ahead of schedule (negative = behind)."""
        return self.current_capital - self.target_today

    @property
    def ahead_pct(self) -> float:
        """Percentage ahead/behind schedule."""
        target = self.target_today
        if target <= 0:
            return 0.0
        return (self.current_capital - target) / target * 100

    @property
    def progress_pct(self) -> float:
        """Progress toward $10,000 from $180."""
        if TARGET_CAPITAL <= START_CAPITAL:
            return 0.0
        return max(0, min(100, (self.current_capital - START_CAPITAL) / (TARGET_CAPITAL - START_CAPITAL) * 100))

    @property
    def win_rate(self) -> float:
        total = self.win_count + self.loss_count
        return self.win_count / total if total > 0 else 0.0

    @property
    def achieved(self) -> bool:
        return self.current_capital >= TARGET_CAPITAL

    def record_trade(self, pnl_cad: float) -> None:
        """Record a completed trade outcome."""
        self.trade_count += 1
        self.total_pnl += pnl_cad
        self.current_capital += pnl_cad
        self.peak_capital = max(self.peak_capital, self.current_capital)
        self.best_trade = max(self.best_trade, pnl_cad)
        self.worst_trade = min(self.worst_trade, pnl_cad)

        if pnl_cad > 0:
            self.win_count += 1
            self.consecutive_wins += 1
            self.consecutive_losses = 0
        elif pnl_cad < 0:
            self.loss_count += 1
            self.consecutive_losses += 1
            self.consecutive_wins = 0

    def daily_snapshot(self) -> dict:
        """Take a snapshot for history tracking."""
        snap = {
            "date": str(date.today()),
            "day": self.day_number,
            "capital": round(self.current_capital, 2),
            "target": round(self.target_today, 2),
            "ahead_by": round(self.ahead_by, 2),
            "ahead_pct": round(self.ahead_pct, 1),
            "progress_pct": round(self.progress_pct, 1),
            "trades": self.trade_count,
            "win_rate": round(self.win_rate, 2),
            "peak": round(self.peak_capital, 2),
        }
        self.history.append(snap)
        return snap

    def position_fraction(self) -> float:
        """How much of account to put in a trade.

        Based on schedule progress:
        - Ahead by >10%: MAX aggression (100%)
        - On track (±10%): Aggressive (95%)
        - Behind 10-30%: Cautious (85%)
        - Behind >30%: Defensive (75%)
        """
        if self.consecutive_losses >= 3:
            return 0.70  # protect from tilt
        if self.consecutive_losses >= 2:
            return 0.80

        ahead = self.ahead_pct
        if ahead > 20:
            return 1.00  # all-in, we're crushing it
        if ahead > 10:
            return 0.98
        if ahead > -10:
            return 0.95  # on track
        if ahead > -30:
            return 0.85  # behind
        return 0.75  # way behind, protect capital

    def status_emoji(self) -> str:
        if self.achieved:
            return "🏆"
        if self.ahead_pct > 20:
            return "🔥"
        if self.ahead_pct > 10:
            return "🚀"
        if self.ahead_pct > 0:
            return "📈"
        if self.ahead_pct > -10:
            return "➡️"
        if self.ahead_pct > -30:
            return "⚠️"
        return "🔴"

    def progress_bar(self, width: int = 10) -> str:
        """ASCII progress bar."""
        filled = int(self.progress_pct / 100 * width)
        return "█" * filled + "░" * (width - filled)

    def weekly_target(self) -> float:
        """Target for the current week."""
        week = (self.day_number - 1) // 5 + 1
        return WEEK_TARGETS.get(week, TARGET_CAPITAL)

    def format_status(self) -> str:
        """Format goal progress for alert message."""
        bar = self.progress_bar()
        emoji = self.status_emoji()
        pos_frac = self.position_fraction()

        lines = [
            f"{emoji} GOAL: ${START_CAPITAL:.0f} → ${TARGET_CAPITAL:,} | Day {self.day_number}/{TRADING_DAYS}",
            f"{bar} {self.progress_pct:.1f}% — ${self.current_capital:.2f}",
            f"Target today: ${self.target_today:.2f} | {self.ahead_pct:+.1f}% vs plan",
            f"Peak: ${self.peak_capital:.2f} | W/L: {self.win_count}/{self.loss_count} ({self.win_rate:.0%})",
            f"Streak: W{self.consecutive_wins}/L{self.consecutive_losses} | Sizing: {pos_frac:.0%}",
        ]

        if self.achieved:
            lines.append(f"🏆🎯 GOAL ACHIEVED! ${self.current_capital:.2f} ≥ ${TARGET_CAPITAL:,}")

        # Show next milestone
        for day_num, target in MILESTONES:
            if self.current_capital < target:
                lines.append(f"Next: ${target:,} (Day {day_num})")
                break

        return "\n".join(lines)


# ──────────────────────────────────────────────────────────────────────
# Persistence
# ──────────────────────────────────────────────────────────────────────

STATE_FILE = Path("trading/storage/state/goal_tracker.json")

def save_goal(goal: GoalProgress, path: Path = STATE_FILE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "start_date": str(goal.start_date),
        "current_capital": goal.current_capital,
        "peak_capital": goal.peak_capital,
        "trade_count": goal.trade_count,
        "win_count": goal.win_count,
        "loss_count": goal.loss_count,
        "total_pnl": goal.total_pnl,
        "best_trade": goal.best_trade,
        "worst_trade": goal.worst_trade,
        "consecutive_wins": goal.consecutive_wins,
        "consecutive_losses": goal.consecutive_losses,
        "history": goal.history[-90:],  # keep last 90 days
    }
    path.write_text(json.dumps(data, indent=2, default=str))


def load_goal(path: Path = STATE_FILE) -> GoalProgress:
    """Load or create fresh goal tracker."""
    if path.exists():
        try:
            data = json.loads(path.read_text())
            return GoalProgress(
                start_date=date.fromisoformat(data["start_date"]),
                current_capital=data["current_capital"],
                peak_capital=data["peak_capital"],
                trade_count=data["trade_count"],
                win_count=data["win_count"],
                loss_count=data["loss_count"],
                total_pnl=data["total_pnl"],
                best_trade=data["best_trade"],
                worst_trade=data["worst_trade"],
                consecutive_wins=data["consecutive_wins"],
                consecutive_losses=data["consecutive_losses"],
                history=data.get("history", []),
            )
        except Exception:
            pass
    return GoalProgress()