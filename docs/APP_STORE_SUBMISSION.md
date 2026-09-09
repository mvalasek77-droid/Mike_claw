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

## Actual App Review outcome — Prompt Coach Lite rejected 2026-09-08

Real rejection, not a predicted one. Apple's message, in full:

> **Submission ID** eeace56f-6a13-498f-a626-a370cd9b04c5 · **Review date**
> September 8, 2026 · **Device** iPad Air 11-inch (M3) · **Version** 1.0 (2)
>
> **Guideline 2.3.7 — Performance — Accurate Metadata**
> The app subtitle include references to the price of the app or the
> service it provides... Note that references to free or discounted
> services are considered a price reference and are not appropriate for
> app metadata. *Next steps: remove any references to pricing from the
> app's metadata.*
>
> **Guideline 4.1(a) — Design — Copycats**
> The app's metadata contains third-party content... Specifically, the
> app's subtitle includes references to Claude. *Next steps: revise the
> app and metadata to remove this third-party content before resubmitting.
> If you have the necessary rights to distribute an app with this
> third-party content, attach documentary evidence and reply to this
> message.*

**Cause, exactly:** the Lite subtitle drafted in this doc's §2 was `Free
Claude Prompt Coaching` — it contains both the flagged words, "Free" (a
price reference, however casually used) and "Claude" (the third-party
trademark). Both guidelines cite the **subtitle specifically**, not the
Name, description, or keywords fields.

**We don't hold documentary rights to use "Claude" as trademark content**
(Prompt Coach is an independent app, not an Anthropic product), so the
4.1(a) "attach evidence" branch doesn't apply — the only real path is
compliance: remove the flagged words from the subtitle and resubmit. This
supersedes the speculative "trademark reply" template in §7 below for this
specific field; that template is for a description/keywords-level dispute,
not a subtitle Apple has already told us plainly to change.

**The fix — already applied in §2 below:**

| | Old (rejected) | New |
|---|---|---|
| Lite subtitle | `Free Claude Prompt Coaching` | `Rewrite Prompts, Learn Why` |

**The paid app's live subtitle has the identical pattern** (`Prompt
Coaching for Claude` — no price word, but it does contain "Claude") and
apparently wasn't flagged when it was reviewed. That's inconsistent
enforcement, not a green light — the same reviewer team just told us in
writing that a subtitle referencing Claude is a 4.1(a) problem. Recommend
proactively fixing the paid subtitle too, on the next update, rather than
waiting for it to get flagged on its own (also updated in §1 below, marked
as precautionary since Apple hasn't required it there yet).

**Resubmission steps (App Store Connect, web only — I can't do this part):**

1. App Store Connect → **Prompt Coach Lite** → the 1.0 version (status
   should read *Rejected* or *Metadata Rejected*).
2. Edit the **Subtitle** field to `Rewrite Prompts, Learn Why`.
3. This is metadata-only — no new build/binary is required, so there's
   nothing to re-archive in Xcode for this fix alone.
4. **Submit for Review** again.
5. Optional: reply to the original message in the Resolution Center
   acknowledging the fix — Apple doesn't require a reply for a metadata-only
   correction, submitting the corrected version is sufficient on its own.
6. Separately, on Prompt Coach's *next* version update, apply the same
   subtitle change there (`5 Models, Prompted Right`) — not urgent, no
   rejection forcing it, but don't let another update ship on the old one.

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
| **Subtitle** (30 char max) | `5 Models, Prompted Right` (24 chars) — changed from `Prompt Coaching for Claude` after Lite was rejected under Guideline 4.1(a) for the identical "Claude in subtitle" pattern; see the Actual App Review outcome section above. Not yet required here by Apple, but the pattern is now a known rejection trigger — apply on the next update. |
| **Bundle ID** | `com.codegenie.promptcoach` |
| **SKU** | `PROMPTCOACH-IOS-2026` (any unique internal string works — this is not user-facing) |
| **Primary category** | Productivity |
| **Secondary category** | Developer Tools |
| **Price** | One-time purchase, **$9.99** (Tier — select the tier that maps to $9.99 USD in ASC's current pricing matrix; the tier *number* Apple assigns to that price point isn't stable enough to print here as a fact) |
| **Availability** | All territories, unless you have a reason to restrict |
| **Age rating** | See §5 — computes to 4+ |
| **In-app purchases** | None. Confirm zero IAP products exist under this app's ASC record before submitting — the app and its Terms both assert this. |
| **Support URL** | `https://mvalasek77-droid.github.io/Mike_claw/prompt-coach-support.html` *(verify — see §7, Pages may not be live yet)* |
| **Marketing URL** | Optional; the support URL works fine here too if you don't want a separate marketing page |
| **Privacy Policy URL** | `https://mvalasek77-droid.github.io/Mike_claw/prompt-coach-privacy.html` |
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

**Not touched by the 2026-09-08 rejection** — both guidelines cited only
the *subtitle*, not keywords. Left as-is deliberately rather than
preemptively stripped: Apple didn't ask for that, and removing accurate
search terms costs discoverability for no confirmed reason. Worth watching
on a future review, but not a documented risk the way the subtitle was —
don't fix what wasn't flagged.

### What's New (this field doesn't apply to a first submission — ASC only
shows it starting with version 2. Leave blank for the 1.0.0 initial submission.)

---

## 2. App Store Connect record — Prompt Coach Lite (free)

| Field | Value |
|---|---|
| **Name** | `Prompt Coach Lite` |
| **Subtitle** (30 char max) | `Rewrite Prompts, Learn Why` (26 chars) — **required fix.** The original `Free Claude Prompt Coaching` was rejected 2026-09-08 under Guideline 2.3.7 ("Free" = price reference) and Guideline 4.1(a) ("Claude" = third-party trademark). See the Actual App Review outcome section above. Paste this value in and resubmit. |
| **Bundle ID** | `com.codegenie.promptcoach.lite` |
| **SKU** | `PROMPTCOACHLITE-IOS-2026` |
| **Primary category** | Productivity |
| **Secondary category** | Developer Tools |
| **Price** | Free |
| **Availability** | All territories |
| **Age rating** | 4+ (see §5, identical questionnaire answers) |
| **In-app purchases** | None. This matters more here than on the paid app — confirm no IAP exists, because a free app that links to a separate paid app can *look* like a 3.1.1 workaround if IAP products exist alongside it. There should be zero IAP products under this app's ASC record, full stop. |
| **Support URL** | `https://mvalasek77-droid.github.io/Mike_claw/prompt-coach-support.html` (same page as the paid app — it already covers both) |
| **Privacy Policy URL** | `https://mvalasek77-droid.github.io/Mike_claw/prompt-coach-lite-privacy.html` |
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

**Also not touched.** Same reasoning as the paid app's keywords above —
both rejection guidelines named the subtitle specifically, not this field.
"free" here is fine; the keyword field isn't the user-visible metadata
2.3.7 is about, and Apple didn't flag it.

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

**Superseded for subtitle-level 4.1(a) flags** — see the *Actual App Review
outcome* section at the top of this doc. When Apple names the subtitle
specifically and we have no documentary rights to offer, the correct move
is removing the word and resubmitting, not arguing the point below. Keep
this template for a different scenario: a future rejection that cites the
*description* or *keywords* for the same reason, where "functional,
factually accurate reference, clearly disclaimed" is a real argument worth
making rather than an easy compliance fix.

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

**Resolved since this doc was first written** (confirmed by commits from the
Mac-side session that actually archived and submitted a build): a real
`DEVELOPMENT_TEAM` is set in `project.yml`; a distinct Lite app icon exists
(`AppIconLite.appiconset`); GitHub Pages is live and the hosted legal/support
URLs were verified HTTP 200 as of 2026-08-06; the paid app was archived,
uploaded, reviewed, and **is live** (per the user, confirmed by the fact
that Lite could even be submitted and reviewed against it).

**Still genuinely open:**

1. **`AppTier.paidAppStoreURL` is still the literal placeholder**
   (`apps.apple.com/app/id0000000000`) in `App/AppTier.swift`, even though
   the paid app is live. This is now the most urgent item: Lite's "Unlock
   all 5 models" card and its three locked model-reference rows all link
   through this constant — if it ships as-is, real users tapping it hit a
   fake App Store page. **Unlike the subtitle fix, this is a code change,
   not metadata** — it needs a new build, archive, and upload, not just an
   App Store Connect edit. **I need the paid app's real numeric App ID**
   (from App Store Connect → Prompt Coach → App Information → General
   Information → Apple ID, or the `id`-number segment of its live App Store
   URL) to patch this — give it to me and I'll fix `AppTier.swift` and
   re-run the contract tests.
2. **Legal entity name for the copyright line** — can't confirm from source
   whether this was filled in on the Mac side; check `§1`/`§2`'s Copyright
   field in ASC directly.
3. A minor test-infra note, not a submission blocker: the new contract check
   for the Anthropic disclaimer had to account for Swift's `\` line-
   continuation syntax splitting the phrase across lines in the source file.
   Worth remembering if you hand-edit `LegalText` later — a contract-test
   substring check on multi-line Swift string literals needs the same
   normalization, or a phrase that happens to wrap a line reads as absent
   even when it's present.

Everything above that's checkable from source **is** checked — run
`python3 ios/PromptCoach/Tests/validate_pack.py` before acting on any of
this. It won't catch a dead Pages URL or a placeholder App Store ID that
merely *looks* like a valid URL; it will catch the hosted legal pages
drifting out of sync with what the app actually does, and — as of this
rejection — a subtitle that reintroduces "free" or "claude"/"anthropic".
