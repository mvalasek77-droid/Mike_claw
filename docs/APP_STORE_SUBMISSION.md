# App Store Connect Submission — Prompt Coach + Prompt Coach Lite

Copy-paste-ready metadata for both listings, plus the "reply" content: what
to put in App Review's Notes field proactively, and ready templates for the
specific rejections this app is most likely to draw. Every claim below is
grounded in what's actually implemented — nothing here describes a roadmap
feature as if it shipped. Where a number depends on Apple's current UI
(exact screenshot pixel sizes, price-tier numbers) I say so rather than
guess, because those shift and a wrong guess here is worse than a gap.

This is content, not code — nothing in this file can be verified from a
Linux container. Treat the field values as a first draft to paste into App
Store Connect and adjust as you go, not as already-submitted truth.

---

## 0. The one thing to fix before anything else

**Do not name the app "Claude Prompt Coach" in App Store Connect.** Several
earlier docs in this repo (and the original hosted-page titles) used that
name. The in-app `CFBundleDisplayName` is already just **"Prompt Coach"** —
keep the ASC **Name** field consistent with that. Leading with a third
party's trademarked product name in your own app's name is a real
App Review / trademark risk (Guideline 4.1-adjacent, and Apple's general
Intellectual Property policy), independent of whether the content itself is
fine. Referring to "Claude," "Anthropic," "Sonnet," "Opus," "Haiku," and
"Fable" *inside* the description and keywords is fine — that's accurate,
functional description of what the app targets — the risk is specifically
in the **app name** implying the product itself.

Both this doc and the code now carry a matching disclaimer everywhere Claude
or Anthropic is mentioned in legal copy: *"Prompt Coach is not affiliated
with, endorsed by, or sponsored by Anthropic."* (see `LegalText` in-app and
the four hosted `prompt-coach*.html` pages). Keep that sentence if you edit
any of that copy later — it's the mitigation for using the model names at
all.

---

## 1. App Store Connect record — Prompt Coach (paid)

| Field | Value |
|---|---|
| **Name** | `Prompt Coach` |
| **Subtitle** (30 char max) | `Prompt Coaching for Claude` (26 chars) |
| **Bundle ID** | `com.codegenie.promptcoach` |
| **SKU** | `PROMPTCOACH-IOS-2026` (any unique internal string works — this is not user-facing) |
| **Primary category** | Productivity |
| **Secondary category** | Developer Tools |
| **Price** | One-time purchase, **$9.99** (Tier — select the tier that maps to $9.99 USD in ASC's current pricing matrix; the tier *number* Apple assigns to that price point isn't stable enough to print here as a fact) |
| **Availability** | All territories, unless you have a reason to restrict |
| **Age rating** | See §5 — computes to 4+ |
| **In-app purchases** | None. Confirm zero IAP products exist under this app's ASC record before submitting — the app and its Terms both assert this. |
| **Support URL** | `https://mvalasek77-droid.github.io/mike_claw/prompt-coach-support.html` *(verify — see §7, Pages may not be live yet)* |
| **Marketing URL** | Optional; the support URL works fine here too if you don't want a separate marketing page |
| **Privacy Policy URL** | `https://mvalasek77-droid.github.io/mike_claw/prompt-coach-privacy.html` |
| **Copyright** | `© 2026 [your legal name or entity]` — fill in; nothing in the repo states a legal entity name |

### Promotional text (170 char max, editable anytime post-launch)

```
Rambling prompt in, model-ready Claude prompt out. Coaches all 5 Claude models, teaches the technique behind every edit. One price, no subscriptions.
```
(149 chars)

### Description

```
Prompt Coach turns a rambling, half-formed prompt into a clean, model-ready
prompt for Claude — and shows you exactly why, so you learn the technique
instead of just getting an answer.

WHAT IT DOES
Type or dictate your prompt the way it actually comes out of your head.
Prompt Coach detects what you're trying to do — write code, debug, draft an
email, summarize a document, and more — picks the Claude model suited to
the job, and rewrites your prompt around real prompt-engineering technique:
a clear role, the right structure, a stated success criterion, examples
where they help. Every edit is labeled, so the app doubles as a lesson.

FIVE MODELS, PROMPTED CORRECTLY
Claude Haiku 4.5, Sonnet 5, Opus 5, Opus 4.8, and Fable 5 don't all want the
same prompt. Prompt Coach knows the differences that actually matter — for
example, it withholds a self-check instruction on Opus 5 (which already
verifies its own work, and telling it to check again makes output worse)
while adding one for Sonnet 5, where it helps. A full model reference
library explains how to prompt each one, browsable any time.

SHARPEN
Take any coached prompt further with a second pass into fully tagged
sections — role, context, task, success criteria — for when you want full
control over the structure.

KNOW WHAT IT COSTS
See an estimated token count and cost for your prompt on the model you
picked, compared against the priciest model in the lineup — so model choice
stops being a guess.

ADAPTS TO YOU
Prompt Coach notices which model you actually pick, which prompts you
sharpen, and which techniques you never use — and shifts its defaults
accordingly, entirely on your device. Every adjustment is listed in plain
language in Settings, and one tap resets it.

EVERYTHING STAYS ON YOUR PHONE
No account. No analytics. No ads. No tracking. The app makes no network
requests — coaching runs entirely on device, and your history never leaves
your iPhone.

ONE PRICE. NO SUBSCRIPTIONS.
Prompt Coach is a one-time purchase. No in-app purchases, no recurring
charges, ever.

Prompt Coach is not affiliated with, endorsed by, or sponsored by
Anthropic.
```

### Keywords (100 char max, comma-separated)

```
prompt engineering,ai prompt,claude,anthropic,chatgpt,writing,productivity,coach,llm,gpt
```
(88 chars)

### What's New (this field doesn't apply to a first submission — ASC only
shows it starting with version 2. Leave blank for the 1.0.0 initial submission.)

---

## 2. App Store Connect record — Prompt Coach Lite (free)

| Field | Value |
|---|---|
| **Name** | `Prompt Coach Lite` |
| **Subtitle** (30 char max) | `Free Claude Prompt Coaching` (27 chars) |
| **Bundle ID** | `com.codegenie.promptcoach.lite` |
| **SKU** | `PROMPTCOACHLITE-IOS-2026` |
| **Primary category** | Productivity |
| **Secondary category** | Developer Tools |
| **Price** | Free |
| **Availability** | All territories |
| **Age rating** | 4+ (see §5, identical questionnaire answers) |
| **In-app purchases** | None. This matters more here than on the paid app — confirm no IAP exists, because a free app that links to a separate paid app can *look* like a 3.1.1 workaround if IAP products exist alongside it. There should be zero IAP products under this app's ASC record, full stop. |
| **Support URL** | `https://mvalasek77-droid.github.io/mike_claw/prompt-coach-support.html` (same page as the paid app — it already covers both) |
| **Privacy Policy URL** | `https://mvalasek77-droid.github.io/mike_claw/prompt-coach-lite-privacy.html` |
| **Copyright** | Same entity as the paid app |

### Promotional text

```
The free way to write better Claude prompts. Coaches Haiku 4.5 and Sonnet 5, explains every technique it applies. No account, no ads, no subscription.
```
(150 chars)

### Description

```
Prompt Coach Lite is the free way to turn a rambling prompt into a clean,
model-ready prompt for Claude — and see exactly why, so you learn the
technique, not just get an answer.

WHAT IT DOES
Type or dictate your prompt the way it actually comes out of your head.
Prompt Coach Lite detects what you're doing, coaches your prompt for Claude
Haiku 4.5 or Claude Sonnet 5, and names every prompt-engineering technique
it applies as it rewrites your ask.

EVERYTHING STAYS ON YOUR PHONE
No account. No analytics. No ads. No tracking. The app makes no network
requests — coaching runs entirely on device.

WANT MORE?
Prompt Coach (full app, one-time purchase, no subscriptions) unlocks all 5
Claude models — including Opus 5 and Fable 5 — plus Sharpen, a token/cost
estimate, unlimited history, and adaptive controls that adjust to how you
work. Prompt Coach Lite links to it; that's the only place this app ever
points off-device.

Prompt Coach Lite is not affiliated with, endorsed by, or sponsored by
Anthropic.
```

### Keywords

```
prompt engineering,ai prompt,claude,anthropic,chatgpt,writing,coach,llm,free,gpt
```
(80 chars)

---

## 3. Screenshots

Neither app has any yet — this repo has no rendered screenshots because
nothing here has ever run in a Simulator (no Xcode in this environment).
Capture these once you've been through `docs/SIMULATOR_TESTING_CHECKLIST.md`.

**Required device classes change with Apple's UI from time to time** — at
minimum today that means a 6.9" iPhone display class (the largest current
iPhone) and, if you check the iPad box for either app, a 13" iPad display
class. **Verify the exact required set in App Store Connect at upload time**
rather than trusting a remembered pixel-dimension table — this is exactly
the kind of Apple-side detail that drifts.

Suggested shot sequence, same for both apps (Lite naturally has fewer
screens available):

1. Ramble → Result, mid-coaching, showing the report card and "what I
   changed" labels — this is the single best screenshot, it's the whole
   product in one frame.
2. Model picker with 5 chips (paid) / 2 chips (Lite) and the per-model tint
   visible.
3. Model reference detail for one model, showing real prompting guidance
   (not the locked-row state for Lite's screenshot — use one of the two
   unlocked models).
4. Technique library, search or a category expanded.
5. (Paid only) Sharpen result with tagged `<role>`/`<task>` sections.
6. (Paid only) Token/cost card.
7. Settings, showing the "Everything runs on your device" footer — privacy
   is a real differentiator here, make it visible.

Capture in both light and dark mode if you have time; submit whichever set
reads better, App Review doesn't require both.

---

## 4. App Privacy ("Nutrition Label") questionnaire

Both apps answer identically, and the honest answer is the simple one:

**"Does this app collect any data?" → No, Data Not Collected.**

This is defensible because it's literally true, not just the easy answer —
`Tests/validate_pack.py` asserts zero `URLSession` usage anywhere in the
codebase, for both targets. There is no analytics SDK, no crash reporter, no
ad network, no account system. Selecting "Data Not Collected" for the whole
questionnaire is correct; don't second-guess it into over-declaring data
collection that doesn't happen.

**Encryption / export compliance:** `Info.plist` already sets
`ITSAppUsesNonExemptEncryption` to `false` for both targets. When ASC asks
"Does your app use encryption?", the consistent answer is **No** (the app
uses only what iOS provides by default, and makes no network calls to even
invoke HTTPS) — this skips the export-compliance documentation step
entirely.

---

## 5. Age rating

Apple's current questionnaire asks for content descriptors. Every one is
answered **None / No** for this app — there's no user-generated content, no
messaging, no web browsing, no violence, no mature themes, nothing
purchasable that isn't the app itself. Answering the full questionnaire
honestly this way computes to the lowest tier (**4+**) for both listings.
There's nothing to argue about here; just don't skip the questionnaire
thinking 4+ is a default — it's a computed result, not a checkbox.

---

## 6. App Review — Notes for the Review Team (submit proactively)

Paste a version of this into the **Notes** field on *both* submissions —
adjust the reference to the sibling app depending on which one you're
submitting.

**For Prompt Coach (paid):**

```
Prompt Coach is a single-purchase app with no account, no server, and no
network activity at all — the coaching engine runs entirely on-device from
a bundled data file (there is nothing to sign into, and no demo credentials
are needed).

There is a companion free app, "Prompt Coach Lite," built from the same
codebase with a fixed, smaller feature set (2 of 5 models; no Sharpen; no
token/cost estimate; no adaptive controls; history capped at 3 sessions).
Prompt Coach Lite links out to this app's own App Store listing as its only
way to "upgrade" — there is no in-app purchase in either app, and no
mechanism that routes around Apple's payment system. The two are simply
separate SKUs, one free and one paid, sharing source code.

Neither app makes any network request. You can confirm this by testing in
Airplane Mode — every feature behaves identically with or without
connectivity.
```

**For Prompt Coach Lite (free):**

```
Prompt Coach Lite is the free, feature-limited counterpart to "Prompt
Coach" (same developer, separate paid App Store listing). It is built from
the same codebase, split by a compile-time flag — there is no shared
runtime state, no server, and no account on either app.

The reduced feature set (2 of 5 Claude models; no Sharpen; no token/cost
estimate; no adaptive controls; history capped at 3 sessions) is
intentional, not an incomplete submission — it's a standard free/paid tier
split. The app links to the paid app's own App Store page in two places
(a Settings card, and locked rows in the model reference library) as its
only way to reference the paid app; there is no in-app purchase, no
paywall UI, and no payment flow inside this app at all.

Like the paid app, Prompt Coach Lite makes no network requests — you can
confirm this in Airplane Mode.
```

## 7. Ready-reply templates for likely rejections

Keep these on hand; don't submit them unless the corresponding rejection
actually happens. Each is grounded in what's real about this submission,
not a generic denial script.

### If flagged under Guideline 3.1.1 (In-App Purchase) — "app appears to
### direct users to purchase outside the app"

This is the single most likely rejection given the two-listing structure,
even though the structure is compliant. Apple's own guidelines explicitly
permit linking to your other apps' own App Store listings; the guideline
targets mechanisms that let a user pay for *digital content or features
inside this app* through an external channel, which doesn't apply here —
there's no purchasable content or feature *inside* Prompt Coach Lite at
all, digital or otherwise.

```
Prompt Coach Lite contains no purchasable content, feature, or
functionality of any kind — everything in the app is free and fully
functional with no upsell, no locked feature behind a purchase prompt
inside this app, and no payment flow. The link to "Prompt Coach" opens
that app's own, separate App Store product page via a standard App Store
URL; Apple's Payments guideline (3.1.1) governs purchases made *within* an
app for digital content used *in* that app, which does not describe this
case — the transaction, if the user chooses to make one, happens entirely
within Apple's own App Store product page for a different app, through
Apple's standard purchase flow, with Apple retaining its standard
commission. We're happy to remove the link entirely if that resolves the
concern, though we'd note plenty of published free/paid app pairs use this
exact pattern.
```

### If flagged under Guideline 2.1 (App Completeness) — "Lite feels too
### limited / incomplete"

```
Prompt Coach Lite is intentionally a free tier of a paid app, not an
incomplete build. Every feature present works fully end-to-end: prompt
coaching, task detection, the technique library, and history are all
complete and functional with no placeholder states, disabled buttons, or
"coming soon" content anywhere in the app. The smaller model set and
absence of Sharpen/adaptive-controls/token-estimate are a deliberate
product decision (a free/paid split), matching the app's own description
and screenshots, not a bug or an unfinished submission.
```

### If flagged under Guideline 2.3.1 / 5.1.1 (Accurate Metadata / Privacy)

```
The app's Privacy Policy and its App Privacy declaration in App Store
Connect both state that no data is collected, and that is accurate: the
app makes zero network requests (verifiable in Airplane Mode) and has no
account system, analytics, or third-party SDK of any kind. If a specific
line in our metadata or Privacy Policy reads as inconsistent with the
app's actual behavior, please point us to it and we'll correct it
immediately — we'd genuinely like to know if something drifted.
```

### If flagged for trademark / naming concerns around "Claude" or
### "Anthropic"

```
Prompt Coach is an independent app that helps users write better prompts
for Anthropic's publicly documented Claude models; it is not named after,
branded to resemble, or presented as an official Anthropic product. The
app's own name is "Prompt Coach" (not "Claude [anything]"), and both the
in-app Terms of Use and the hosted Privacy/Terms pages state explicitly:
"Prompt Coach is not affiliated with, endorsed by, or sponsored by
Anthropic." References to Claude, Sonnet, Opus, Haiku, and Fable in the
app and its listing are factual and functional — they describe which
models the app's coaching guidance targets — not a claim of affiliation.
```

---

## 8. Still open — cannot be resolved from this repo alone

1. **`AppTier.paidAppStoreURL` is a placeholder** (`apps.apple.com/app/id0000000000`)
   in `App/AppTier.swift`. It must point at the real listing before Lite
   ships, which means the paid app needs to go live (and get a real numeric
   App ID) before Lite's in-app link is meaningful. Submitting Lite first
   with the placeholder still live would ship a dead link inside the app —
   avoid that ordering.
2. **Confirm GitHub Pages is actually serving `docs/` at the URL used
   throughout this doc.** The deploy workflow
   (`.github/workflows/deploy-pages.yml`) previously only triggered on a
   different branch (`claude/ai-marketplace-ios-app-iUYui`); it's now been
   updated to also trigger on this branch, but that only takes effect once
   this branch is pushed and the workflow actually runs. Check
   **Settings → Pages** in the GitHub repo to confirm Pages is enabled at
   all and confirm the resulting URL matches `mvalasek77-droid.github.io/mike_claw/`
   — there's no `CNAME` file, so there's no custom domain configured, and I
   can't confirm from here whether Pages has ever been turned on for this
   repo. If the URLs in §1–§2 don't resolve, this is why — fix Pages first,
   the ASC fields are correct once the pages are actually live.
3. **`DEVELOPMENT_TEAM` is blank** in `project.yml` — needed to archive and
   upload a build at all, separate from any of the metadata above.
4. **Both apps need real icons.** Lite currently inherits the paid app's
   placeholder icon (see `project.yml` — both targets point at the same
   `AppIcon` asset catalog entry). They should look related but distinct —
   a common pattern is the same mark with a visibly different treatment
   (outline vs. filled, a corner badge) so both are recognizable as the same
   family without being visually identical in a screenshot comparison.
5. **Legal entity name for the copyright line** — nothing in the repo states
   one; fill in `§1`/`§2`'s Copyright field before submitting.
6. A minor test-infra note, not a submission blocker: the new contract check
   for the Anthropic disclaimer had to account for Swift's `\` line-
   continuation syntax splitting the phrase across lines in the source file.
   Worth remembering if you hand-edit `LegalText` later — a contract-test
   substring check on multi-line Swift string literals needs the same
   normalization, or a phrase that happens to wrap a line reads as absent
   even when it's present.

Everything above that's checkable from source **is** checked — run
`python3 ios/PromptCoach/Tests/validate_pack.py` (567 checks as of this
writing) before acting on any of this. It won't catch a dead Pages URL or a
missing icon; it will catch the hosted legal pages drifting out of sync with
what the app actually does, which is the failure mode most likely to sink
an actual review.
