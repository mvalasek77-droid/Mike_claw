"""Risk-signal engine.

Turns account snapshots into neutral, factual safety signals for parents.

Wording policy (enforced by tests): signals state observable facts and suggest
a parent action. They NEVER label a person — no "predator", "groomer", "MAP",
or similar accusations. That policy is both an App Review requirement (apps
that name-and-shame individuals get rejected) and a defamation guardrail.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Optional

from .roblox_client import RobloxPresence, RobloxProfile
from .threat_feed import ThreatFeed

FORBIDDEN_LABELS = ("predator", "groomer", "map", "pedophile", "offender")


class Severity(str, Enum):
    INFO = "info"          # worth knowing, no action needed
    WATCH = "watch"        # keep an eye on it, maybe start a conversation
    ELEVATED = "elevated"  # talk with your child soon; review together


class SignalType(str, Enum):
    NEW_FRIEND = "new_friend"
    OFF_PLATFORM_HANDLE = "off_platform_handle"
    GROOMING_PHRASE = "grooming_phrase"
    ESTABLISHED_ACCOUNT_CONTACT = "established_account_contact"
    LARGE_NETWORK_CONTACT = "large_network_contact"
    RAPID_FRIENDING = "rapid_friending"
    FLAGGED_EXPERIENCE = "flagged_experience"
    QUIET_HOURS_ACTIVITY = "quiet_hours_activity"


@dataclass
class Signal:
    type: SignalType
    severity: Severity
    title: str
    facts: list[str]
    guidance: str
    subject_user_id: Optional[int] = None
    subject_username: Optional[str] = None
    observed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


_REPORT_GUIDANCE = (
    "If anything about this contact worries you, block and report the account "
    "through Roblox's in-app Report Abuse feature. If you believe your child is "
    "being asked for images, personal details, or off-platform contact by an "
    "adult, report it to the NCMEC CyberTipline (report.cybertip.org) or your "
    "local police."
)


def _account_age_years(profile: RobloxProfile, now: datetime) -> float:
    return (now - profile.created).days / 365.25


def evaluate_new_friend(
    friend: RobloxProfile,
    feed: ThreatFeed,
    now: Optional[datetime] = None,
    established_years: float = 5.0,
    mass_friender_threshold: int = 700,
) -> list[Signal]:
    """Signals for a single newly-added friend.

    All text patterns come from the threat feed, so detection keeps up with
    new platforms and slang without code changes. Bio, display name, and
    username are all scanned — handles hide in display names too.
    """
    now = now or datetime.now(timezone.utc)
    signals: list[Signal] = []
    age_years = _account_age_years(friend, now)

    # Feed thresholds override caller defaults when present.
    established_years = float(feed.thresholds.get(
        "established_account_years", established_years))
    mass_friender_threshold = int(feed.thresholds.get(
        "mass_friender_threshold", mass_friender_threshold))

    facts = [
        f"Account created {friend.created.date().isoformat()} ({age_years:.1f} years ago).",
    ]
    if friend.friend_count is not None:
        facts.append(f"Has {friend.friend_count} friends on Roblox.")

    scanned_text = " \n ".join(
        [friend.description or "", friend.display_name or "", friend.username or ""])

    matches = feed.match_off_platform(scanned_text)
    if matches:
        platforms = [m["platform"] for m in matches]
        handle_facts = facts + [
            f"Profile includes contact details for: {', '.join(platforms)}.",
            "Moving conversations to private apps removes Roblox's chat filters and moderation.",
        ]
        if any(m["obfuscated"] for m in matches):
            obfuscated = [m["platform"] for m in matches if m["obfuscated"]]
            handle_facts.append(
                f"The {', '.join(obfuscated)} reference is written with character "
                "substitutions (e.g. 'd1sc0rd') — a technique used to slip past "
                "Roblox's text filters."
            )
        signals.append(Signal(
            type=SignalType.OFF_PLATFORM_HANDLE,
            severity=Severity.ELEVATED,
            title=f"New friend's profile advertises contact outside Roblox ({', '.join(platforms)})",
            facts=handle_facts,
            guidance=(
                "Ask your child how they know this account and whether anyone has "
                "asked them to chat on another app. Agree together that chats stay "
                "on Roblox where filters apply. " + _REPORT_GUIDANCE
            ),
            subject_user_id=friend.user_id,
            subject_username=friend.username,
        ))

    phrases = feed.match_grooming_phrases(scanned_text)
    if phrases:
        signals.append(Signal(
            type=SignalType.GROOMING_PHRASE,
            severity=Severity.ELEVATED,
            title=f"New friend's profile contains high-risk contact phrases",
            facts=facts + [
                f"Profile text contains: {', '.join(repr(p) for p in phrases)}.",
                "These phrases match patterns used to initiate private, secret, or "
                "image-based contact with children.",
            ],
            guidance=(
                "Ask your child directly whether this account has messaged them and "
                "what about. Review the friendship together. " + _REPORT_GUIDANCE
            ),
            subject_user_id=friend.user_id,
            subject_username=friend.username,
        ))

    extra_context: list[str] = []
    if age_years >= established_years:
        extra_context.append(
            f"This account is {age_years:.1f} years old — much older than typical accounts in a child's friend group."
        )
    if friend.friend_count is not None and friend.friend_count >= mass_friender_threshold:
        extra_context.append(
            f"This account has {friend.friend_count} friends, close to Roblox's 1,000-friend cap — "
            "a pattern of adding very many people."
        )

    if extra_context:
        signals.append(Signal(
            type=(SignalType.LARGE_NETWORK_CONTACT
                  if friend.friend_count is not None and friend.friend_count >= mass_friender_threshold
                  else SignalType.ESTABLISHED_ACCOUNT_CONTACT),
            severity=Severity.WATCH,
            title=f"New friend “{friend.display_name or friend.username}” has an unusual account profile",
            facts=facts + extra_context,
            guidance=(
                "None of this proves anything on its own. Ask your child where they "
                "met this account (a game? a group?) and whether they know them in "
                "real life. " + _REPORT_GUIDANCE
            ),
            subject_user_id=friend.user_id,
            subject_username=friend.username,
        ))

    if not signals:
        signals.append(Signal(
            type=SignalType.NEW_FRIEND,
            severity=Severity.INFO,
            title=f"New friend added: {friend.display_name or friend.username}",
            facts=facts,
            guidance="A good moment to ask your child about their new friend.",
            subject_user_id=friend.user_id,
            subject_username=friend.username,
        ))
    return signals


def evaluate_rapid_friending(
    new_friend_count: int,
    window_hours: int,
    threshold: int,
) -> Optional[Signal]:
    if new_friend_count < threshold:
        return None
    return Signal(
        type=SignalType.RAPID_FRIENDING,
        severity=Severity.WATCH,
        title=f"{new_friend_count} new friends added in the last {window_hours} hours",
        facts=[
            f"Your child's account added {new_friend_count} friends within {window_hours} hours.",
            "Fast friend-list growth often comes from public servers where strangers mass-send requests.",
        ],
        guidance=(
            "Consider reviewing the new friends together and tightening who can "
            "send friend requests in Roblox's privacy settings (Settings → Privacy)."
        ),
    )


def evaluate_presence(
    presence: RobloxPresence,
    watchlist: dict[int, dict],
    quiet_start: int,
    quiet_end: int,
    local_now: Optional[datetime] = None,
) -> list[Signal]:
    """Signals from a single presence observation.

    `watchlist` maps placeId -> {"name": ..., "reason": ...} for experiences the
    operator has curated as higher-risk (e.g. weak-moderation social hangouts).
    """
    signals: list[Signal] = []
    local_now = local_now or datetime.now().astimezone()

    if presence.presence_type == 2 and presence.place_id in watchlist:
        entry = watchlist[presence.place_id]
        signals.append(Signal(
            type=SignalType.FLAGGED_EXPERIENCE,
            severity=Severity.WATCH,
            title=f"Playing a watchlisted experience: {entry.get('name', presence.last_location or 'unknown')}",
            facts=[
                f"Observed in experience “{entry.get('name', presence.last_location)}” (place {presence.place_id}).",
                f"Watchlist note: {entry.get('reason', 'flagged by your watchlist')}.",
            ],
            guidance=(
                "Ask your child what they like about this experience and who they "
                "play it with. You can restrict allowed experiences with Roblox's "
                "parental controls (content maturity settings)."
            ),
        ))

    if presence.presence_type in (1, 2):
        hour = local_now.hour
        in_quiet = (quiet_start <= hour or hour < quiet_end) if quiet_start > quiet_end \
            else (quiet_start <= hour < quiet_end)
        if in_quiet:
            signals.append(Signal(
                type=SignalType.QUIET_HOURS_ACTIVITY,
                severity=Severity.INFO,
                title=f"Online during quiet hours ({local_now.strftime('%H:%M')})",
                facts=[f"Account was active at {local_now.strftime('%H:%M')} local time, inside your configured quiet hours."],
                guidance=(
                    "Late-night sessions are when kids are least supervised. Roblox's "
                    "parental controls can enforce a schedule if you want one."
                ),
            ))
    return signals


def validate_wording(signal: Signal) -> None:
    """Guardrail used by tests and at emit time: signals must stay factual."""
    text = " ".join([signal.title, signal.guidance, *signal.facts]).lower()
    for label in FORBIDDEN_LABELS:
        if re.search(rf"(?<![a-z]){re.escape(label)}(?![a-z])", text):
            raise ValueError(f"Signal wording must not label people ({label!r} found)")
