"""Plain-language layer for parents who know nothing about Roblox.

Two pieces:

  ROBLOX_BASICS   A from-zero explainer ("What is Roblox?", "What are
                  Robux?") served at /education and shown in the app.

  GLOSSARY        Term definitions with aliases. `explain(text)` finds every
                  glossary term appearing in a piece of text, so alerts and
                  reports can attach "words used here" boxes automatically —
                  no alert ever assumes the reader knows Roblox.

Definitions are written for a reader with zero gaming background, one or two
sentences, concrete, no metaphors that need their own explanation.
"""

import re

ROBLOX_BASICS = [
    {
        "id": "what_is_roblox",
        "question": "What is Roblox?",
        "answer": (
            "Roblox is not one game — it's a place where millions of small "
            "games (Roblox calls them 'experiences') live, most of them made "
            "by other users. Your child picks a cartoon-like character (an "
            "'avatar') and can jump between games, play alongside strangers "
            "from anywhere in the world, and message other players. Think of "
            "it as a giant playground where anyone, of any age, can walk in."
        ),
    },
    {
        "id": "what_are_robux",
        "question": "What are Robux?",
        "answer": (
            "Robux is Roblox's money. It's bought with real money and spent on "
            "outfits, accessories, and game extras. Kids value Robux the way "
            "they value cash — which is exactly why adults with bad intentions "
            "give Robux as gifts: it builds gratitude and obligation. If your "
            "child has Robux or items you didn't buy, ask where they came from."
        ),
    },
    {
        "id": "how_friends_work",
        "question": "How do 'friends' work on Roblox?",
        "answer": (
            "Anyone your child meets in any game can send them a friend "
            "request — a stranger becomes a 'friend' with one tap. Friends can "
            "chat privately and see when your child is online. A Roblox "
            "friend is NOT like a school friend: your child may know nothing "
            "about who is really behind the account, including their age."
        ),
    },
    {
        "id": "how_chat_works",
        "question": "Can people talk to my child?",
        "answer": (
            "Yes — by text chat inside games and in private messages, and in "
            "some games by voice. Roblox filters chat for younger players "
            "(blocking phone numbers, addresses, and profanity), but people "
            "get around the filter with tricks like writing 'd1sc0rd' instead "
            "of 'discord'. Important: no outside app — including this one — "
            "can read your child's private chats. Only Roblox's own "
            "moderators can, which is why reporting inside Roblox matters."
        ),
    },
    {
        "id": "what_is_a_profile",
        "question": "What is a profile or 'bio'?",
        "answer": (
            "Every account has a public page anyone can see: a picture of "
            "their avatar, a short self-description (the 'bio'), their friend "
            "list, and when they joined. This app reads these public pages — "
            "when a new friend's bio says 'message me on Snapchat', that's "
            "visible to anyone, and it's a warning sign this app will flag."
        ),
    },
    {
        "id": "why_other_apps",
        "question": "Why do alerts mention Discord, Snapchat, or Telegram?",
        "answer": (
            "Those are chat apps with little or no protection for children. "
            "The single most common move in documented abuse cases: meet a "
            "child on Roblox, then say 'let's talk on Discord instead'. The "
            "moment the conversation leaves Roblox, every safety filter and "
            "moderator disappears. That's why an account advertising these "
            "app names to children is this app's most serious alert."
        ),
    },
    {
        "id": "what_are_condos",
        "question": "What are 'condo games'?",
        "answer": (
            "Slang for hidden adult games inside Roblox — rooms with sexual "
            "content and conversation where adults and children mix. Roblox "
            "deletes them constantly, but they reappear under new names "
            "within hours. They're usually found through invitations, often "
            "shared on Discord."
        ),
    },
    {
        "id": "what_can_parents_control",
        "question": "What controls does Roblox itself give me?",
        "answer": (
            "Quite a lot, and they're free: a parent account linked to your "
            "child's lets you limit who can chat with them, cap screen time "
            "and spending, and restrict mature content. This app tells you "
            "WHEN to worry; Roblox's own controls are how you change what "
            "your child can do. Set both up — the Get Help tab links to "
            "Roblox's parental controls."
        ),
    },
]

# term -> (aliases, definition). Aliases are matched as whole words,
# case-insensitively, against alert/report text.
GLOSSARY: dict[str, dict] = {
    "Robux": {
        "aliases": ["robux"],
        "definition": "Roblox's virtual money, bought with real money. Gifts of Robux from strangers are a common trust-building tactic.",
    },
    "bio": {
        "aliases": ["bio", "bios"],
        "definition": "The short public self-description on a Roblox account's profile page. Anyone can read it.",
    },
    "profile": {
        "aliases": ["profile"],
        "definition": "An account's public page: avatar picture, self-description, friend list, and join date. Visible to anyone, no login needed.",
    },
    "experience": {
        "aliases": ["experience", "experiences"],
        "definition": "Roblox's word for a game or virtual place inside Roblox. Most are made by other users, not by Roblox itself.",
    },
    "friend request": {
        "aliases": ["friend request", "friend requests"],
        "definition": "An invitation to connect. On Roblox any stranger met in any game can send one; accepting lets them chat privately with your child.",
    },
    "friend list": {
        "aliases": ["friend list", "friends on roblox", "friend-list"],
        "definition": "The public list of accounts your child has accepted as friends. Friends can message your child and see when they're online.",
    },
    "account age": {
        "aliases": ["account created", "years old"],
        "definition": "How long ago the account was registered. A years-old account contacting young children doesn't fit the usual pattern of a child's friend group.",
    },
    "Discord": {
        "aliases": ["discord"],
        "definition": "A chat app popular with gamers, with voice, video, and private servers — and no child-safety filtering like Roblox's. The most common destination when someone tries to move a child's conversation off Roblox.",
    },
    "Snapchat": {
        "aliases": ["snapchat", "snap"],
        "definition": "A messaging app where photos and messages disappear after viewing — which makes it attractive for anyone who doesn't want a record of what they send to a child.",
    },
    "Telegram": {
        "aliases": ["telegram"],
        "definition": "A messaging app with encrypted and disappearing chats and effectively no child-safety moderation.",
    },
    "off-platform": {
        "aliases": ["off-platform", "off roblox", "outside roblox", "another app", "private apps", "outside apps"],
        "definition": "Moving a conversation from Roblox to a different app (Discord, Snapchat, etc.). This removes Roblox's filters and moderators — it's the pivot point in nearly every documented grooming case.",
    },
    "chat filter": {
        "aliases": ["chat filter", "chat filters", "text filters", "roblox's filters"],
        "definition": "Roblox's automatic censoring of risky text (phone numbers, addresses, profanity) in children's chats. People evade it with spelling tricks — which is itself a warning sign.",
    },
    "character substitution": {
        "aliases": ["character substitution", "character substitutions", "d1sc0rd"],
        "definition": "Spelling tricks like writing 'd1sc0rd' (with a one and a zero) so the word 'discord' slips past Roblox's automatic filters. Deliberate evasion like this shows intent.",
    },
    "presence": {
        "aliases": ["online status", "was active", "observed in experience"],
        "definition": "Whether an account is currently online and which game it's in. Roblox shows this publicly for most accounts.",
    },
    "watchlist": {
        "aliases": ["watchlist", "watchlisted"],
        "definition": "A curated list of Roblox games flagged as higher-risk (for example, poorly moderated social hangouts). Maintained as part of this app's threat intelligence.",
    },
    "friend cap": {
        "aliases": ["1,000-friend cap", "friend cap"],
        "definition": "Roblox limits accounts to 1,000 friends. An account near the cap has been adding people in bulk — a pattern seen in accounts that trawl games friending many children.",
    },
    "Report Abuse": {
        "aliases": ["report abuse"],
        "definition": "Roblox's built-in reporting button, available on every profile, chat, and game. Reports go to Roblox's moderators, who can read the actual messages and ban accounts.",
    },
    "CyberTipline": {
        "aliases": ["cybertipline", "report.cybertip.org", "ncmec"],
        "definition": "The US national reporting center for online child exploitation (run by the National Center for Missing & Exploited Children). Reports reach law enforcement. Free, and you don't need proof to file — suspicion is enough.",
    },
    "parental controls": {
        "aliases": ["parental controls"],
        "definition": "Roblox's free settings for parents: limit who can chat with your child, cap spending and screen time, and restrict mature content. Set up from a linked parent account.",
    },
    "sextortion": {
        "aliases": ["sextortion"],
        "definition": "Blackmail using an intimate image: once someone has (or fakes) one image of a child, they threaten to share it unless the child sends more, or money. Report to police immediately; never pay; the child is the victim, not in trouble.",
    },
}


def merged_glossary(feed=None) -> dict[str, dict]:
    """Static glossary merged with feed-delivered entries (feed wins).

    The threat feed can add terms ("what is <new app>?") or reword existing
    definitions fleet-wide without an app release.
    """
    merged = dict(GLOSSARY)
    for entry in getattr(feed, "glossary", None) or []:
        term = entry.get("term")
        definition = entry.get("definition")
        if not term or not definition:
            continue
        merged[term] = {
            "aliases": list(entry.get("aliases") or [term.lower()]),
            "definition": definition,
        }
    return merged


def merged_basics(feed=None) -> list[dict]:
    """Roblox-101 entries merged with feed overrides (matched by id)."""
    merged = {entry["id"]: entry for entry in ROBLOX_BASICS}
    for entry in getattr(feed, "roblox_basics", None) or []:
        if entry.get("id") and entry.get("question") and entry.get("answer"):
            merged[entry["id"]] = {"id": entry["id"], "question": entry["question"],
                                   "answer": entry["answer"]}
    return list(merged.values())


def explain(*texts: str, feed=None) -> list[dict]:
    """Glossary entries for every term appearing in the given texts.

    Returns [{term, definition}] sorted by first appearance, so an alert or
    report section can render a 'words used here' box with no manual tagging.
    """
    combined = " \n ".join(t or "" for t in texts).lower()
    found: list[tuple[int, dict]] = []
    for term, entry in merged_glossary(feed).items():
        positions = []
        for alias in entry["aliases"]:
            pattern = r"(?<!\w)" + re.escape(alias.lower()).replace(r"\ ", r"[\s-]") + r"(?!\w)"
            match = re.search(pattern, combined)
            if match:
                positions.append(match.start())
        if positions:
            found.append((min(positions), {"term": term, "definition": entry["definition"]}))
    found.sort(key=lambda pair: pair[0])
    return [entry for _, entry in found]
