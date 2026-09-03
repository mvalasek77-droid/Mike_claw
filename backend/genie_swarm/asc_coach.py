"""The App Store Connect coach.

**Why this exists.** CodeGenie already ships a deterministic walkthrough
for each submission step — fixed click-by-click instructions that never
hallucinate. That covers the happy path and nothing else. The moment a
user goes off it ("Apple rejected me for guideline 2.1", "my build says
Invalid Binary", "what even is a provisioning profile") the canned text
has no answer and the user is stranded on Apple's console with no help.

This module is the other half: a conversational coach that knows the
submission process, knows where *this specific user* is stuck, and
answers in plain English. The deterministic walkthrough remains the
spine; the coach is for everything either side of it.

**Why the curriculum is hard-coded rather than retrieved.** Apple's
console changes slowly and its hard limits do not change at all. A
fixed, reviewed curriculum is cheaper, faster, works offline-ish, and —
most importantly — cannot drift. The model is told, explicitly and
repeatedly, to answer from this text and to admit ignorance rather than
invent a button. That distinction is the whole difference between a
useful coach and a confident liar.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .llm import LLMClient
from .models import Message


# ---------------------------------------------------------------------------
# The curriculum — what the coach is schooled on
# ---------------------------------------------------------------------------
#
# Everything here is stable, publicly documented Apple behaviour. Keep
# it factual and keep it current; this is the coach's entire world.

ASC_CURRICULUM = """
## The shape of the whole process

Getting an iPhone app to other people has two finish lines, and
conflating them is the single most common source of confusion.

1. TestFlight — a real, installable build for you and people you
   invite. Needs: an app record, a signed build uploaded and processed.
   Does NOT need: icon, screenshots, description, keywords, price,
   privacy answers. This is the first finish line and most people
   should stop here first.
2. The public App Store — anyone can search and download it. Needs
   everything above PLUS the full listing, a 1024x1024 icon,
   screenshots, App Privacy answers, pricing, and a human App Review.

A TestFlight build can be promoted to the App Store later. Same binary,
no rebuild.

## The accounts and sites, and why there are several

- Apple ID — the login you already have.
- Apple Developer Program — a paid membership, 99 USD per year,
  enrolled at developer.apple.com. Without it you cannot ship to
  TestFlight or the App Store at all. Enrolment approval can take a
  day or more, sometimes longer for organisations.
- App Store Connect (appstoreconnect.apple.com) — where you manage
  apps, builds, listings, testers, and submission.
- Developer Portal (developer.apple.com/account) — where identifiers,
  certificates, and provisioning profiles live. Beginners usually only
  come here to register a bundle identifier.

## Vocabulary, in plain terms

- Bundle ID — the app's permanent unique name, like com.yourname.tides.
  It must match exactly between the Xcode project and the App Store
  Connect record or the upload is rejected. It cannot be changed after
  the app is on the store.
- SKU — a private reference string you invent. Never shown to anyone.
  Reusing the bundle ID is completely fine.
- .ipa — one sealed, signed file containing the whole app. This is what
  gets uploaded. Producing it requires a Mac with Xcode: an "archive"
  build followed by an "export" for App Store distribution.
- Signing / certificate / provisioning profile — Apple's proof that the
  build came from you. Modern Xcode manages these automatically when
  you let it ("Automatically manage signing"), which is what almost
  everyone should do.
- Processing — after upload, Apple scans the build. It shows as
  "Processing" in the TestFlight tab, usually 5 to 30 minutes.
- App Review — a human at Apple opening your app. Typically 24 to 48
  hours. Only for the public App Store, plus a lighter automated review
  for the first external TestFlight build.

## Apple's hard limits — these are server-enforced, not suggestions

- App name: 30 characters. Must be unique across the entire App Store.
- Subtitle: 30 characters.
- Keywords: ONE comma-separated field, 100 characters TOTAL including
  the commas. It is not 100 per word. This trips up nearly everyone.
- Description: 4000 characters.
- Promotional text: 170 characters. Changeable without a new review.
- App icon: exactly 1024x1024 PNG, no alpha channel, no transparency,
  no pre-rounded corners. Apple rounds corners itself.
- Screenshots: at least one iPhone display size. A 6.9-inch capture
  (1320 x 2868) lets Apple scale down to the others.
- Support URL: required, and Apple actually loads it.
- Privacy Policy URL: required, even when the app collects nothing.

## Creating the app record — the New App dialog, field by field

Apps -> the blue + near the top-left -> New App.

- Platforms: tick iOS.
- Name: the public App Store name.
- Primary Language.
- Bundle ID: chosen from a dropdown. If yours is missing it has not
  been registered yet — go to developer.apple.com/account ->
  Certificates, Identifiers & Profiles -> Identifiers -> + , register
  it, then reload the App Store Connect page.
- SKU: any private string.
- User Access: Full Access is the normal choice.

## Testers

- Internal testers: people already listed under Users and Access on
  your team. Up to 100. Instant, no review. You must add yourself here
  to install your own build.
- External testers: anyone else, up to 10,000, by email or a public
  link. The first build for external testers gets a light automated
  Apple review, usually under a day. Later builds are instant.
  External testing requires a "What to Test" note and a contact email.

## Export compliance

Asked on nearly every upload. If you did not add your own encryption,
the answer is No. Using HTTPS or Apple's standard APIs does not count
as adding encryption. Answering wrong here can hold a build.

## App Privacy

App Store Connect -> App Privacy -> Get Started. If the app stores
everything on the device and transmits nothing, answer that you do not
collect data. If you added analytics, crash reporting, accounts, or any
server that receives user data, answer yes and declare it honestly.
Apple audits this after release and a false answer can pull a live app.

## Pricing

Pricing and Availability -> Free is the safe default for a first app,
and can be changed later without a new review. Charging money requires
completed bank and tax details under Business, which can take days to
clear.

## Submitting

On the app's App Store page: under Build click + and pick a build that
finished processing. Answer Export Compliance, Content Rights, and
Advertising Identifier. Then Add for Review -> Submit for Review. Apple
requires the account holder to do this; it cannot be automated.

## Common rejections and what they actually mean

- Guideline 2.1 Performance, App Completeness — usually a crash on
  Apple's device, a broken feature, or placeholder content. Also
  triggered by a missing demo account when your app has a login.
- Guideline 4.2 Minimum Functionality — the app is too thin, or is
  essentially a repackaged website.
- Guideline 5.1.1 Data Collection — asking for data you do not need, or
  requiring an account for features that do not need one.
- Guideline 2.3 Accurate Metadata — screenshots or description do not
  match what the app does. Placeholder or lorem-ipsum screenshots are a
  frequent cause.
- Missing Privacy Policy URL, or a support URL that does not load.

Rejections arrive in Resolution Center with the exact guideline number.
Most first-app rejections are metadata or account issues and need no
code change or rebuild — you fix the listing and resubmit.

## Build status problems

- Build never appears in TestFlight: check email. Apple sends binary
  rejections by email and does not always show them in the console.
- "Invalid Binary": usually a missing icon, an unsupported architecture,
  or a bad Info.plist.
- "Missing Compliance": answer the export compliance question on the
  build.
- Build appears but cannot be installed: you are probably not added as
  an internal tester yet.
"""


SYSTEM_PROMPT = f"""
You are CodeGenie's App Store Connect coach. You are talking to someone
who has never submitted an app to Apple before, inside an iPhone app,
while they are part-way through submitting their own app.

Answer only from the curriculum below plus the user's live situation.

{ASC_CURRICULUM}

## How to answer

- Plain English. No jargon unless you immediately define it. Never say
  "simply" or "just".
- Short. Two or three sentences for a simple question. Use a numbered
  list only when the answer genuinely is a sequence of clicks.
- Concrete. Name the actual button, tab, or field, and where it sits on
  the page.
- Ground every answer in where they actually are. You are told their
  current step, what is blocking them, and their app's details. Use
  them. Refer to their app by name.
- End with the one thing to do next, unless you have just answered a
  pure definition question.

## Hard rules

- Never invent App Store Connect interface. If you are not certain a
  control exists or where it is, say you are not certain and describe
  how to find it instead. Being wrong about a button sends someone on a
  ten-minute hunt and destroys their trust in everything else you said.
- Never claim you performed an action. You give advice. CodeGenie's own
  buttons are what upload, validate, and fill fields. If the user needs
  a CodeGenie action, tell them which button in the app to tap.
- Never guess at Apple's numeric limits. They are listed above. If a
  limit is not listed, say you do not know it.
- Do not give legal, tax, or accounting advice. For anything about
  contracts, bank details, or tax forms, say it is outside what you can
  help with and point them at Apple's Business section.
- If the user asks something unrelated to shipping an app, say that is
  outside what you cover here and steer back.
- If a question depends on something you cannot see — the contents of
  their rejection email, what their app does — ask for that one detail
  rather than assuming.
"""


# ---------------------------------------------------------------------------
# Live situation
# ---------------------------------------------------------------------------

@dataclass
class CoachContext:
    """Everything the coach knows about where this user actually is.

    Assembled by the iOS client, which is the only side that knows the
    live UI state. Every field is optional so a partially-wired caller
    still gets a useful answer rather than a validation error.
    """
    app_name: str = ""
    bundle_id: str = ""
    step_number: int | None = None
    step_title: str = ""
    completed_steps: list[int] = field(default_factory=list)
    mac_paired: bool = False
    blocking_issues: list[str] = field(default_factory=list)
    outstanding_items: list[str] = field(default_factory=list)
    total_steps: int = 12

    def render(self) -> str:
        lines = ["## Where this user is right now"]
        lines.append(f"- Their app is called: {self.app_name or 'not named yet'}")
        if self.bundle_id:
            lines.append(f"- Bundle ID: {self.bundle_id}")
        if self.step_number is not None:
            lines.append(
                f"- Currently on step {self.step_number} of {self.total_steps}"
                + (f': "{self.step_title}"' if self.step_title else "")
            )
        done = len(self.completed_steps)
        lines.append(f"- Steps finished so far: {done} of {self.total_steps}")
        lines.append(
            "- A Mac is connected, so CodeGenie can open App Store Connect and type fields for them."
            if self.mac_paired
            else "- No Mac is connected. Every step still works by hand on the phone, but CodeGenie cannot type into App Store Connect for them, and it cannot package the app for upload."
        )
        if self.blocking_issues:
            lines.append("- Their listing currently has problems Apple would reject:")
            lines.extend(f"    - {i}" for i in self.blocking_issues[:8])
        if self.outstanding_items:
            lines.append("- Release checks still outstanding:")
            lines.extend(f"    - {i}" for i in self.outstanding_items[:8])
        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Suggested questions
# ---------------------------------------------------------------------------
#
# A blank chat box is intimidating and, worse, a first-timer does not
# know what they are allowed to ask. Seeding each step with the
# questions people actually have there turns the coach from a feature
# into something they use.

_STEP_PROMPTS: dict[int, list[str]] = {
    1:  ["Which Apple ID should I sign in with?", "Why does it say I don't have permission?"],
    2:  ["What is a bundle ID?", "My bundle ID isn't in the dropdown", "What should I put for SKU?"],
    3:  ["What is an .ipa?", "Why does it say no .ipa was found?", "Do I really need a Mac?"],
    4:  ["How long does processing take?", "My build never showed up"],
    5:  ["How do I get the app on my phone?", "I never got the invite email"],
    6:  ["Internal vs external testers?", "How do I share a public link?"],
    7:  ["What are Apple's icon rules?", "My icon was rejected for transparency"],
    8:  ["What screenshots do I need?", "What size should screenshots be?"],
    9:  ["How do keywords work?", "What should I write in the description?"],
    10: ["Do I collect data if everything stays on the phone?", "Do I need a privacy policy?"],
    11: ["Should my app be free?", "Can I change the price later?"],
    12: ["What happens after I submit?", "What if Apple rejects my app?"],
}

_GENERAL_PROMPTS = [
    "What's the difference between TestFlight and the App Store?",
    "How much does this cost?",
    "How long will the whole thing take?",
]


def suggested_questions(step_number: int | None) -> list[str]:
    """Questions worth offering at this point in the flow."""
    if step_number is None:
        return list(_GENERAL_PROMPTS)
    return _STEP_PROMPTS.get(step_number, []) + _GENERAL_PROMPTS[:1]


# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------

MAX_HISTORY_TURNS = 12


async def answer(
    *,
    llm: LLMClient,
    question: str,
    context: CoachContext,
    history: list[Message] | None = None,
    model: str = "claude-sonnet-5",
    max_tokens: int = 900,
) -> dict[str, Any]:
    """Answer one coaching question.

    The live situation is appended to the system prompt rather than
    injected as a user turn, so a long conversation cannot push it out
    of the window and the model cannot mistake it for something the
    user typed.
    """
    question = (question or "").strip()
    if not question:
        return {"answer": "", "usage": {}}

    turns = list(history or [])[-MAX_HISTORY_TURNS:]
    turns.append(Message(role="user", content=question))

    response = await llm.complete(
        model=model,
        system=f"{SYSTEM_PROMPT}\n\n{context.render()}",
        messages=turns,
        tools=[],
        max_tokens=max_tokens,
        # Low but not zero: this is explanation, not code generation.
        temperature=0.3,
    )
    return {"answer": response.text, "usage": response.usage}
