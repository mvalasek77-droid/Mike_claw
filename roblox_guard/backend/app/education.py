"""Structured safety-education content.

Distilled from docs/ROBLOX_DANGERS.md. Served to the app via /education and
woven into incident reports so a report reader (parent, officer, NCMEC
analyst) gets the danger pattern explained next to the observed facts.

Wording note: this content discusses predatory behavior in general terms.
The per-person labeling guardrail in signals.py still applies to anything
said about a specific account.
"""

DANGER_CATALOG = [
    {
        "id": "grooming_contact",
        "title": "Grooming & predatory contact",
        "summary": (
            "Adults pose as children, enter experiences popular with young kids, "
            "and initiate contact through chat or friend requests. Research on "
            "gaming platforms shows first contact can turn high-risk within 19 "
            "seconds, with a median grooming arc of about 45 minutes."
        ),
        "progression": [
            "Contact: friend request or chat in a social experience.",
            "Trust-building: flattery, attention, posing as a peer; emotionally "
            "vulnerable kids are deliberately selected.",
            "Gifts: Robux transfers, game passes, items — unexplained Robux is a "
            "major red flag.",
            "Isolation: 'don't tell your parents', private servers, then moving "
            "off-platform to Discord/Snapchat/Telegram.",
            "Escalation: photo requests, sexual conversation, sextortion, or "
            "attempts to meet in person.",
        ],
        "related_signals": ["off_platform_handle", "established_account_contact",
                            "large_network_contact", "new_friend"],
    },
    {
        "id": "off_platform_funnel",
        "title": "The off-platform funnel",
        "summary": (
            "The most dangerous single moment is when chat moves off Roblox to "
            "Discord, Snapchat, or Telegram: filters, moderation, and parental "
            "visibility all vanish at once. Nearly every family lawsuit in the "
            "federal MDL against Roblox describes this pivot. A profile "
            "advertising off-platform handles to a child is the highest-value "
            "warning signal available."
        ),
        "progression": [
            "A contact's bio or chat advertises a Discord/Snap/Telegram handle "
            "or phone number.",
            "The child installs the app 'because a friend asked'.",
            "Conversation continues where no filter or moderator can see it.",
        ],
        "related_signals": ["off_platform_handle"],
    },
    {
        "id": "sextortion",
        "title": "Sextortion",
        "summary": (
            "Once one sexual image is obtained (or fabricated with AI), it "
            "becomes blackmail: send more, send money, or it gets shared. The "
            "fastest-growing category of CyberTipline reports; teen boys are "
            "targeted at scale by financially motivated rings. Presents as "
            "sudden severe distress. Do not pay, do not delete anything, report "
            "to police and report.cybertip.org immediately."
        ),
        "progression": [
            "Trust or romance established, often quickly.",
            "One image is coerced, traded, or fabricated.",
            "Threats begin: money, more images, or exposure to friends/family.",
        ],
        "related_signals": ["off_platform_handle", "quiet_hours_activity"],
    },
    {
        "id": "condo_games",
        "title": "'Condo' games and sexual content",
        "summary": (
            "User-generated sexual environments are uploaded faster than "
            "moderation removes them, advertised through Discord and coded "
            "search terms. Inside: explicit avatar animation and roleplay, with "
            "adults mixing freely with children."
        ),
        "progression": [
            "Invitation via chat, group, or off-platform server.",
            "Short-lived experience joined before moderation takes it down.",
            "Contact continues in private servers or off-platform.",
        ],
        "related_signals": ["flagged_experience"],
    },
    {
        "id": "filter_evasion",
        "title": "Chat-filter evasion",
        "summary": (
            "Roblox filters under-13 chat, but contacts evade filters with "
            "leetspeak ('d1sc0rd'), spacing, in-world signs, and voice chat. "
            "Deliberately writing around the filter demonstrates intent."
        ),
        "progression": [],
        "related_signals": ["off_platform_handle"],
    },
    {
        "id": "financial",
        "title": "Scams and financial exploitation",
        "summary": (
            "'Free Robux' phishing sites harvest credentials; 'beaming' steals "
            "accounts and items; gambling-adjacent mechanics condition kids to "
            "wager; and predators use Robux gifts to create obligation."
        ),
        "progression": [],
        "related_signals": ["new_friend"],
    },
]

# Signs only a parent can observe — surfaced in the app's education screens
# and in every incident report.
BEHAVIORAL_SIGNS = [
    "Secrecy: switching screens when you walk in, new passcodes, deleted chats, "
    "anger when asked about online friends.",
    "A new 'special' friend — especially older, especially one who gives things: "
    "unexplained Robux, gift cards, game passes, or real-world gifts.",
    "Sexual language or knowledge beyond their age.",
    "Anxiety, dread, or compulsive checking tied to the game; withdrawal from "
    "real-world friends.",
    "Discord, Snapchat, or Telegram newly installed 'because a friend asked'.",
    "Late-night play or messaging; sleep changes.",
    "Sudden severe distress with refusal to explain — classic sextortion "
    "presentation; act the same day.",
]

IMMEDIATE_RED_FLAGS = [
    "An online contact asked the child for photos of themselves — of any kind.",
    "Asked the child to keep the friendship secret.",
    "Asked to move chat to another app.",
    "Offered Robux, gifts, or money 'for favors'.",
    "Threatened to share images or information (sextortion — report to police "
    "and report.cybertip.org immediately; do not pay, do not delete).",
    "Suggested meeting in person.",
]

RESPONSE_PLAYBOOK = [
    "Stay calm and don't punish — the child is the victim, and punishment "
    "teaches kids to hide the next incident.",
    "Preserve evidence BEFORE blocking: screenshot chats, profiles, and "
    "usernames on the child's device; blocking can make chat history "
    "inaccessible. EXCEPTION: never screenshot, save, or forward sexual images "
    "of a minor — that is illegal even with protective intent; describe them "
    "to investigators instead.",
    "Do not confront the suspected account — it destroys evidence and can "
    "trigger retaliation.",
    "Report in-platform with Roblox's Report Abuse on the profile and chat.",
    "File a CyberTipline report (report.cybertip.org) for any sexual "
    "solicitation, image request, or threat. In an emergency call 911.",
    "Lock down the account: privacy to Friends-only, enable Roblox parental "
    "controls with a parent PIN, review the friend list together.",
    "Export this app's incident report and bring it to police/NCMEC — it "
    "contains the timeline, observed facts, and hash-verified evidence.",
]


def education_payload(feed=None) -> dict:
    from .glossary import merged_basics, merged_glossary
    return {
        "roblox_basics": merged_basics(feed),
        "dangers": DANGER_CATALOG,
        "behavioral_signs": BEHAVIORAL_SIGNS,
        "immediate_red_flags": IMMEDIATE_RED_FLAGS,
        "response_playbook": RESPONSE_PLAYBOOK,
        "glossary": [{"term": t, "definition": e["definition"]}
                     for t, e in merged_glossary(feed).items()],
    }


def dangers_for_signal_types(signal_types: set[str]) -> list[dict]:
    """Danger-catalog entries relevant to a set of observed signal types."""
    return [d for d in DANGER_CATALOG
            if signal_types.intersection(d["related_signals"])]
