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

from .llm import COACH_MODEL, LLMClient
from .models import ASC_TOTAL_STEPS, Message


# ---------------------------------------------------------------------------
# The curriculum — what the coach is schooled on
# ---------------------------------------------------------------------------
#
# Everything here is stable, publicly documented Apple behaviour. Keep
# it factual and keep it current; this is the coach's entire world.

ASC_CURRICULUM = """
## The shape of the whole process

Getting an iPhone app to other people has two finish lines, and
conflating them is the single most common source of confusion. Between
them sits testing, which is what decides whether the second one is
reached on the first try.

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

CodeGenie's guide has 23 steps in four parts: get it on your phone
(steps 1-8, mostly in Xcode on the user's Mac), test it (9-11), prepare
the store page (12-20), and Apple's review (21-23). The user does the
Mac part themselves, following instructions; nothing on the Mac is
automated, so never tell them CodeGenie will click something there.

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

(Xcode usually registers the bundle ID automatically once a team is
chosen. If it is missing from the dropdown, register it by hand at
developer.apple.com -> Certificates, Identifiers & Profiles ->
Identifiers -> +.)


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

## Getting the project into Xcode — the user does this by hand

There is no helper app on the Mac. CodeGenie packs the project as a
zip; the user AirDrops it from the phone to the Mac (it lands in
Downloads), unzips it, and opens the file ending in .xcodeproj. If the
Mac does not appear in AirDrop: Finder -> AirDrop -> "Allow me to be
discovered by: Everyone". Fallback: Save to Files -> iCloud Drive.

Xcode is free from the Mac App Store, Mac-only, and a very large
download. First launch may install extra components and the iOS
platform — let it. Sign in under Xcode -> Settings -> Accounts -> + ->
Apple Account.

## Signing in Xcode

Click the blue project icon at the top of the left sidebar, select the
app under TARGETS, open the Signing & Capabilities tab, tick
"Automatically manage signing", and choose a Team.

- Only "Personal Team" offered: the Developer Program membership is not
  active on that Apple ID. A personal team can run on the user's own
  phone but cannot upload to App Store Connect.
- "Failed to register bundle identifier": that ID is taken by someone
  else. The identifier must change in Xcode AND the app record must be
  created with the new one — never one without the other.
- "No account for team" / "No profiles found": sign in again under
  Settings -> Accounts, then re-select the team.

## Running in the Simulator

Pick an iPhone under iOS Simulators in the destination menu at the top
of the window and press Run (the triangle, or Command-R). First build
takes minutes. "Build Failed" with a red marker means a compile error:
the user should copy the first error and bring it back. They should not
edit code themselves; CodeGenie can rebuild with the error fixed.

## Archiving and uploading from Xcode

Destination must be "Any iOS Device (arm64)" — Product -> Archive is
greyed out while a simulator is selected. When the archive finishes the
Organizer opens: Distribute App -> App Store Connect -> Distribute (on
older Xcode: Upload, then Next through the defaults).

- "No suitable application records were found": the bundle ID in Xcode
  does not match an app record in App Store Connect. Create the record,
  or fix the mismatch.
- "The bundle version must be higher than the previously uploaded
  version": raise Build by one under the General tab and archive again.
- "Missing required icon" or "Missing Info.plist value": the build was
  rejected on upload; it needs fixing in the project, which means a
  rebuild in CodeGenie.

## Testing — why it is not optional

The app was generated by AI. Compiling proves the code is valid, not
that the app does what was asked. Guideline 2.1 (the app did not work
when the reviewer tried it) is Apple's most common rejection.

CodeGenie gives each app a test plan: fresh install, the main task,
every button, each promised feature, quit and relaunch, no network,
refusing permissions, leftover placeholder text, Dark Mode, large text.
Each test states what to do and what should happen. Be strict: "mostly
works" is a failure. A failed test with one line describing what
happened is passed to a rebuild; after a rebuild the user archives,
uploads and tests again. The App Store steps stay closed until the
required tests pass.

A second person matters because the builder unconsciously avoids the
broken paths. Ask them to do the main task and say nothing; every
hesitation is a finding.

When the situation lists failed tests, address those first.

## Age rating

App Information -> Age Rating. A questionnaire, not a number you pick:
violence, mature themes, medical content, gambling, contests,
unrestricted web access, user-generated content. Apple derives the
rating. Understating it (for example answering None with chat or an
in-app browser present) is checked after release and can pull the app.

## App Review Information

On the version page. Contact name, phone, email. Sign-In Required with
a working test username and password if the app has any login. Notes
telling the reviewer what the app does and where to tap first. A test
account that has expired, needs a verification code, or opens to an
empty screen counts as no account.

## Submitting

On the version page: under Build click + and pick a build that finished
processing. Answer Export Compliance and Content Rights. Choose Version
Release: manual (you press Release after approval) or automatic. Then
Add for Review -> Submit for Review. Add for Review alone sends
nothing; the status must read Waiting for Review. Apple requires the
account holder to do this; it cannot be automated.

## What the review statuses mean

- Prepare for Submission / Ready for Review: not submitted yet, or
  bounced before reaching the queue (a red banner says why).
- Waiting for Review: in the queue. Most apps are picked up within a
  day. Editing the build or cancelling loses the place in the queue.
- In Review: a person has it open. Minutes to a few hours. Keep any
  server or test account running.
- Rejected: the app fell short of a guideline. Needs a fix; may need a
  new build.
- Metadata Rejected: only the store page needs changing. Same build is
  reused; no rebuild.
- Invalid Binary: automated checks failed the upload. Reason arrives by
  email. Needs a new build.
- Developer Rejected: someone on the account withdrew it. Not a
  judgement.
- Pending Developer Release: approved, waiting for the developer to
  press Release This Version.
- Processing for Distribution: approved and propagating. Up to 24 hours.
- Ready for Distribution (formerly Ready for Sale): live. Search can lag
  the direct link by hours.

## Responding to a rejection

The message is under App Review on the app's page in App Store Connect
and names a guideline number. Fix exactly what it describes, reply in
that same thread saying what changed, then resubmit. Do not resubmit
unchanged and do not argue the rule. If the reviewer misread the app,
reply politely with specifics; if that fails, there is a formal appeal
under Contact Us. Resubmitting as many times as needed is normal.

## Common rejections and what they actually mean

- Guideline 2.1 Performance, App Completeness — usually a crash on
  Apple's device, a broken feature, or placeholder content. Also
  triggered by a missing demo account when your app has a login.
- Guideline 4.2 Minimum Functionality — the app is too thin, or is
  essentially a repackaged website. Needs real added functionality, not
  a better argument.
- Guideline 4.3 Spam — too similar to existing apps or to a common
  template. Applied strictly to apps that look generated from a shared
  starting point. A reply alone rarely works: the app needs a genuine
  point of difference in content, audience or features. Renaming and
  recolouring is not enough. Be honest with the user about this.
- Guideline 4.8 Login Services — third-party sign-in without an
  equivalent privacy-focused option such as Sign in with Apple.
- Guideline 1.2 User-Generated Content — needs reporting, blocking and
  filtering.
- Guideline 3.1.1 In-App Purchase — digital goods sold outside Apple's
  purchase system.
- Guideline 5.1.1 Data Collection — asking for data you do not need,
  requiring an account for features that do not need one, a permission
  prompt that does not explain itself, or account creation without
  in-app account deletion.
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
    total_steps: int = ASC_TOTAL_STEPS

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
            "- They are doing the Mac steps by hand in Xcode. CodeGenie cannot see their Mac: "
            "ask what the screen shows rather than assuming."
        )
        if self.blocking_issues:
            lines.append("- Their listing currently has problems Apple would reject:")
            lines.extend(f"    - {i}" for i in self.blocking_issues[:8])
        if self.outstanding_items:
            lines.append("- Testing and release checks so far:")
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
    1:  ["My Mac doesn't show up in AirDrop", "Can I use iCloud Drive instead?", "Do I really need a Mac?"],
    2:  ["Which file do I open in Xcode?", "Xcode is asking to install components", "How do I sign in to Xcode?"],
    3:  ["It only shows Personal Team", "What is a bundle identifier?", "Xcode says failed to register bundle identifier"],
    4:  ["Xcode says Build Failed", "The simulator is taking forever", "How do I use the simulator?"],
    5:  ["My bundle ID isn't in the dropdown", "What should I put for SKU?", "It says I don't have permission"],
    6:  ["Archive is greyed out", "No suitable application records were found", "It says the bundle version must be higher"],
    7:  ["How long does processing take?", "My build never showed up", "What is Missing Compliance?"],
    8:  ["How do I get the app on my phone?", "I never got the invite email"],
    9:  ["Why do I have to test it?", "A test failed — what now?", "What counts as it working?"],
    10: ["Internal vs external testers?", "How do I share a public link?", "What should I ask my tester to do?"],
    11: ["Is my app ready to submit?", "What happens when I rebuild?"],
    12: ["What are Apple's icon rules?", "My icon was rejected for transparency"],
    13: ["What screenshots do I need?", "How do I take a screenshot in the simulator?"],
    14: ["How do keywords work?", "What should I write in the description?", "What can I use as a support URL?"],
    15: ["Do I collect data if everything stays on the phone?", "Do I need a privacy policy?"],
    16: ["How do I answer the age rating questions?", "What counts as unrestricted web access?"],
    17: ["Should my app be free?", "Can I change the price later?"],
    18: ["What should I write in the review notes?", "Do I need to give Apple a test account?"],
    19: ["My build isn't in the list", "What is export compliance?", "Manual or automatic release?"],
    20: ["What happens after I submit?", "What does Add for Review do?"],
    21: ["How long does review take?", "Can I speed up the review?", "Can I change something while I wait?"],
    22: ["What does this rejection mean?", "Do I need to upload a new build?", "How do I reply to App Review?", "Can I appeal?"],
    23: ["Why can't I find my app in search?", "How do I ship an update?"],
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
    model: str = COACH_MODEL,
    max_tokens: int = 4000,
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
        effort="low",
    )
    return {"answer": response.text, "usage": response.usage}
