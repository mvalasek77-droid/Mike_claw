"""
Configuration for the Lottery Pattern Bot.
Defines lottery rules, ranges, and strategy parameters.
"""

LOTTERIES = {
    "lottomax": {
        "name": "Lotto Max",
        "numbers_picked": 7,
        "number_range": (1, 50),
        "bonus": True,
        "draws_per_week": 2,  # Tue & Fri
        "draw_days": ["Tuesday", "Friday"],
        "url": "https://www.playnow.com/services2/lotto/draw/lmax",
        "backup_url": "https://www.lottomaxnumbers.com/numbers",
    },
    "lotto649": {
        "name": "Lotto 6/49",
        "numbers_picked": 6,
        "number_range": (1, 49),
        "bonus": True,
        "draws_per_week": 2,  # Wed & Sat
        "draw_days": ["Wednesday", "Saturday"],
        "url": "https://www.playnow.com/services2/lotto/draw/649",
        "backup_url": "https://www.lotto649numbers.com/numbers",
        # SPECIAL RULE: 1 winning number from prior draw or adjacent
        "prior_draw_rule": True,
        "prior_draw_min_matches": 1,
    },
    "bc49": {
        "name": "BC/49",
        "numbers_picked": 6,
        "number_range": (1, 49),
        "bonus": True,
        "draws_per_week": 2,  # Wed & Sat
        "draw_days": ["Wednesday", "Saturday"],
        "url": "https://www.playnow.com/services2/lotto/draw/bc49",
        "backup_url": None,
    },
}

# Strategy parameters
STRATEGY = {
    # Every second draw has a number that appears in future draws
    "alternating_future_link": True,
    "alternating_interval": 2,

    # Lotto 6/49: at least 1 number from prior draw (or adjacent +/- 1)
    "lotto649_prior_draw_link": True,

    # Pattern detection thresholds
    "min_pattern_confidence": 0.15,
    "min_pair_frequency": 3,
    "min_triplet_frequency": 2,

    # How many past draws to analyze
    "lookback_window": 100,
    "deep_lookback": 500,

    # Evolution parameters
    "learning_rate": 0.05,
    "mutation_rate": 0.02,
    "max_generations": 1000,
    "extinction_threshold": 0.01,  # If accuracy drops below this, reset and rebuild

    # Cross-lottery transfer
    "cross_lottery_enabled": True,
    "transfer_weight": 0.3,
}

DATA_DIR = "data"
PREDICTIONS_DIR = "predictions"
BRAIN_STATE_FILE = "brain/brain_state.json"
EVOLUTION_LOG = "brain/evolution_log.jsonl"
