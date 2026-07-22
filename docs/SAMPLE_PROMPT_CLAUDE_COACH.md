# Sample CodeGenie prompt — Claude Prompt Coach (v2)

Paste-in-ready brief for CodeGenie's *Describe an app* screen. This is the
second revision: the app's whole point is now sharper — **take a rambling,
stream-of-consciousness prompt and turn it into a clean prompt tailored to
the exact Claude model it's headed to** (Sonnet 5, Opus 4.8, or Fable 5),
with a model-profile system that can be updated when new models ship.

Business decisions baked in this revision:

- **Paid up front, no IAP.** One-time App Store price (suggested **$9.99**).
  No subscriptions, no consumables, no account, no paywall inside the app.
- **Terms of Use + Privacy Policy** shipped in-app (Settings → Legal) and
  hosted as web pages for App Store Connect:
  - Privacy: `docs/prompt-coach-privacy.html`
  - Terms: `docs/prompt-coach-terms.html`

## What changed from v1

| v1 | v2 |
|---|---|
| Generic "turn prompts into reusable Skills" | Core loop is **ramble in → model-ready prompt out**, tuned per target model |
| No model awareness | Three Model Profiles (Sonnet 5, Opus 4.8, Fable 5) with real per-model coaching rules |
| No upgrade story | Profiles live in a versioned, refreshable "model pack" so future models slot in without an app update |
| Pricing unspecified | Paid up front, no IAP |
| No legal | Terms of Use + Privacy Policy screens and hosted pages |

## The model facts the app is built on (verified July 2026)

| Model | ID | API price (in/out per MTok) | Coach's one-liner |
|---|---|---|---|
| Claude Sonnet 5 | `claude-sonnet-5` | $3 / $15 (intro $2 / $10 through Aug 2026) | Fast, near-Opus on coding. Follows instructions **literally** — be explicit about scope, it won't infer what you didn't ask for. |
| Claude Opus 4.8 | `claude-opus-4-8` | $5 / $25 | Long-horizon workhorse. Give the **full task spec up front** in one well-specified turn; say *when* tools/capabilities should trigger. |
| Claude Fable 5 | `claude-fable-5` | $10 / $50 | Frontier reasoning. **Don't over-prescribe** — state the goal, constraints, and the *why*; step-by-step scaffolding actually reduces quality. |

Cross-model rules the coach enforces (all three models): no "set temperature"
advice — these models reject sampling parameters, steer with words instead;
no prefill tricks (removed); stable context first, question last; always
include an acceptance test ("done means…").

**The full, expanded per-model rewrite rules — the actual research behind these
profiles — live in `docs/CLAUDE_MODEL_PROMPTING_NOTES.md`, and the
machine-readable model pack the app loads is `docs/model-pack.json`.** The
Model Profile summaries in the prompt below are the short form; the notes doc
and JSON are the source of truth. When Anthropic ships a new model, add an entry
to `model-pack.json` and bump `pack_version` — no app update needed.

## The prompt (paste this into DescribeAppView)

**Title:** `Claude Prompt Coach`

**Prompt (paste into the What should it do? field):**

```
An iPhone app that takes rambling, stream-of-consciousness prompts and
turns them into clean, model-ready prompts for Anthropic's Claude
models. Home screen: a big text box that says "Just ramble." The user
types or dictates whatever is in their head — half-formed, out of
order, contradictory is fine.

When they tap Coach It, the app first RECOMMENDS the cheapest model
that fits the task (Haiku 4.5 for simple/high-volume work, Sonnet 5 as
the default, Opus 4.8 for long autonomous jobs, Fable 5 only for the
hardest reasoning) with a one-line reason and the price — the user can
accept the suggestion or override it with a segmented control. This is
the efficiency win: most rambles don't need an expensive model, and the
app steers away from overpaying by default.

The app then produces three things:
1. The rewritten prompt, tailored to the chosen model, in a card the
   user can copy or share with one tap.
2. A "What I changed" list: each edit with a one-line reason
   ("Moved your constraint up front", "Added an acceptance test",
   "Cut the three restatements of the same ask", "Recommended Haiku —
   this is a formatting task, no need to pay for Opus").
3. A "Why this works on [model]" note, two or three sentences.

Each model has a Model Profile that drives the rewrite rules:
- Haiku 4.5 profile: cheapest and fastest, but shallow. The coach keeps
  the prompt simple and concrete, one clear task with an explicit output
  shape, and if the ramble actually needs reasoning it suggests moving
  up to Sonnet 5 rather than piling instructions onto Haiku.
- Sonnet 5 profile: this model follows instructions literally and
  won't infer unstated scope. The coach makes scope explicit ("apply
  to every section, not just the first"), turns vague asks into
  concrete deliverables, and keeps prompts tight — great for
  high-volume and structured tasks.
- Opus 4.8 profile: strongest on long, autonomous work. The coach
  consolidates the ramble into one complete up-front spec (goal,
  inputs, constraints, definition of done), adds explicit "use X
  when Y" trigger lines for any tools or steps mentioned, and adds
  an autonomy line ("pick reasonable defaults for small decisions,
  ask only on scope changes").
- Fable 5 profile: deepest reasoner; over-prescriptive prompts make
  it worse. The coach strips step-by-step micromanagement down to
  goal + constraints + acceptance test, and adds a "why" sentence
  ("I'm building X for Y; they need Z") because Fable performs
  better when it knows the intent behind the ask.
Rules that apply to every model: never suggest temperature or
sampling settings (current Claude models don't accept them — steer
with words); no prefill tricks; stable context before the question;
every prompt ends with how the user will judge success.

Model Profiles are data, not code: a bundled, versioned JSON "model
pack" (name, model ID, pricing, strengths, rewrite rules, do/don't
list). A Model Pack screen in Settings shows the pack version and a
Check for Updates button that fetches a newer pack from a static URL,
so when Anthropic ships a new model it appears in the picker without
an App Store update. Unknown future models fall back to the
cross-model rules. Each profile card also shows current API pricing
so users can pick the cheapest model that fits the job.

A History tab keeps past coaching sessions on device — original
ramble, chosen model, rewritten prompt — searchable, with a re-run
button to re-coach an old ramble against a different model.

Optional power feature: the user can paste their own Anthropic API
key (stored in the iOS Keychain, never leaving the device except in
calls to Anthropic) to enable a Test It button that runs the
polished prompt against the chosen model and shows the reply, so
they can compare before/after quality. The app works fully without
a key — coaching itself runs on device.

Settings → Legal has Terms of Use and Privacy Policy screens
(bundled HTML, no network needed). Monetization: paid up front on
the App Store, no in-app purchases, no subscriptions, no account,
no analytics, no tracking. Nothing the user types ever leaves the
phone except optional Test It calls to Anthropic with their own key.

Style: iOS 26 Liquid Glass. Warm neutral palette, one accent color
per model (Haiku amber, Sonnet teal, Opus indigo, Fable ember) so the whole
screen subtly re-tints when you switch targets. Haptic tick on
Coach It. Dark mode by default.
```

## Pricing rationale (for App Store Connect)

- **$9.99, Tier paid-up-front.** No IAP products to configure, no
  StoreKit subscription plumbing, no receipt validation server.
- Comparable one-shot utility apps sit $4.99–$14.99; $9.99 signals
  "pro tool" without needing a trial.
- The optional Test It feature costs the *user's own* Anthropic key,
  so the app has zero marginal cost per user.

## Legal pages

Both pages follow the same standalone pattern as
`docs/robloxguard-privacy.html` (self-contained HTML, no external CSS),
so they can be linked directly from App Store Connect once GitHub Pages
serves the `docs/` folder:

- `docs/prompt-coach-privacy.html` — everything on device; no
  collection, no analytics, no ads; optional API key in Keychain, sent
  only to Anthropic; App Store handles payment so we never see it.
- `docs/prompt-coach-terms.html` — one-time purchase, personal-use
  license, no warranty on generated prompts, user is responsible for
  their own Anthropic API costs, Apple standard EULA applies.

Ship the same copy in-app as bundled HTML under Settings → Legal.

## How to use this

1. Open CodeGenie
2. Tap **Start a new build**
3. In *Describe an app*:
   - Title: `Claude Prompt Coach`
   - What should it do?: paste the prompt block above
4. Confirm the cost estimate
5. Watch the build

If the swarm asks follow-ups mid-build: the Model Profile bullets above
are the canonical answers for "what should the rewrite actually do per
model", and the pricing/legal sections answer any monetization or
compliance questions.
