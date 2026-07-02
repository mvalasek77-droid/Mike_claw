# Sample CodeGenie prompt — Claude Prompt Coach

Audited and rewritten from the raw video-transcript notes so it's a clean,
paste-in-ready brief for CodeGenie's *Describe an app* screen. The two source
videos (6 Power Phrases · 4 Rules) are really one product idea: an app that
turns Claude interactions into **reusable Skills**, not just one-shot prompts.

---

## What I cut from the raw notes

Removed as nonsensical, redundant, or off-topic for what you'd actually type
into CodeGenie's prompt field:

| Cut | Why |
|---|---|
| Every timestamp (`0:26`, `3:14` …) and speaker attribution | UI copy has no room for source citations; the ideas stand alone |
| "Sync to video" / "Chapter N" scaffolding | YouTube UI artefacts |
| The channel plug ("if this is your first video…", "our anti-slop agreement", "subscribe") | Marketing filler |
| Anecdote about "checking 10,000 domains programmatically" | Anthropic-team example, not a feature of the app you're building |
| Every "So basically…", "So the reality is…", "So conceptually…" stem | Fillers that pad without adding meaning |
| The layered "AI models → agents → prompts → skills" pyramid graph description | Interesting framing but not a feature — belongs in an About screen at best |
| The `user_invocable` / `disable_model_invocation` flags detail | Real concept, but too advanced for a first-time user of a prompt-coaching app; surface later as a Power-User toggle |

## What I kept as first-class features

The distilled 6 + 4 turned into concrete UI:

- **Interview me** — coach asks 3-5 targeted questions before drafting
- **Draft as a Skill** — output is not a one-shot prompt, it's a
  description + step-by-step instructions + optional tools
- **Spec first** — for anything non-trivial, produce a short spec doc
  before the prompt
- **Launch sub-agents** — for complex asks, split into parallel prompts
  with a synth prompt at the end
- **Verify before you build** — appended verification checklist for
  high-risk steps
- **Compose don't clone** — the app chains small Skills instead of one
  giant prompt; new skills reference existing ones
- **Skills get smarter** — after each session, coach asks *"Should we
  capture what we learned into the Skill?"* and updates it
- **The taste test** — a lightweight "Should this be a Skill or a
  one-off?" gate before saving, so the library doesn't fill with junk

## The prompt (paste this into DescribeAppView)

**Title:** `Claude Prompt Coach`

**Prompt (paste into the What should it do? field):**

```
An iPhone app that turns rough prompts into hyper-focused, reusable
Claude Skills. On open, the user taps New Coach Session and describes
what they're trying to do in one sentence. The app interviews them
with 3-5 short questions to fill gaps — goal, audience, acceptance
test, edge cases — then drafts a Skill: a titled description, step-by-
step instructions, and (optionally) attached tools like scripts,
schemas, or reference files.

Four coaching modes shown as pill buttons on the session screen:
- Interview me: the flip-the-script mode above
- Spec first: draft a short implementation spec before the prompt,
  so ambiguity is resolved on paper first
- Launch sub-agents: for complex asks, split into 3-5 parallel
  sub-agent prompts plus a synth prompt that combines the outputs
- Verify before you build: append a checklist of things the model
  should validate itself against before touching real files or APIs

A Library tab collects saved Skills. Every Skill card shows its
title, one-line description, how many times used, and a heat trail
showing when it was updated. Tap a Skill to open — the user sees the
description, instructions, tools, plus a Chain button that lets them
compose it with other Skills (e.g. Interview Me chained with Debug
Code). Ship with a starter library of five Skills so the first-time
user has something to try: Draft Email, Debug This Code, Write PR
Description, Interview Me, Build A Skill From Our Chat.

After each session, the app asks 'Should we capture what we learned?'
If yes, the used Skill is updated with new rules, examples, or edge
cases the session revealed. Small heart-beat indicator on the Skill
card shows it evolved. Never modify a Skill silently.

A Taste Test dialog before saving asks two yes/no questions: Will you
use this more than 3 times? Would the output be better than the last
five times you did it manually? If both yes, save as a Skill; if not,
save as a one-off note instead.

Style: iOS 26 Liquid Glass. Warm neutral palette with a single accent
that pulses on 'Skill updated' moments. Haptic on save. Dark mode by
default. Everything on-device — no account, no server. The user's
prompts are theirs and never leave the phone unless they explicitly
share a Skill.
```

## How to use this

1. Open CodeGenie
2. Tap **Start a new build**
3. In *Describe an app*:
   - Title: `Claude Prompt Coach`
   - What should it do?: paste the prompt block above
4. Confirm the cost estimate
5. Watch the build

If the swarm asks follow-ups mid-build, the questions in the *Interview
me* section above are good stock answers. The output should be a
runnable app with the four coach modes, a Library tab with 5 starter
Skills, and the after-session capture dialog.

## Concerns triaged (from the same message)

Not shipping any of these in this doc — they're follow-up asks.
Ordered by leverage:

| Concern | What to do about it | Effort |
|---|---|---|
| ASC submit works, and when it doesn't tell the user clearly | Add a `!creds.hasCompanionPairing` short-circuit in `AppStoreConnectGuideView.driveOnMac()` that opens PairMacView instead of firing the 412'd network call. Currently the copy says "Use manual steps below" — should also **surface a big "Pair a Mac first" pill** at the top when Companion missing. | 30 min |
| Way to go back to app if it needs fixing | Pause + resume plumbing already exists (`swarm.pause` / `swarm.unpause`). The `PauseStatusBadge` shows in the top bar but doesn't say the phrase "Pause and come back later". Rename button label + add an explanatory hint. | 15 min |
| Continue from where it stopped | `swarm.resume(jobID:)` exists but is only reachable from the failure overlay. Add a **"Resume interrupted build"** callout on HomeView when there's an unfinished job in `session.recentJobs`. | 45 min |
| Test every function and process | The four-agent audits (docs/FOUR_AGENT_REVIEW.md) walk 17-99 rows through this. Missing the real-device pass on Codex's compiled build — that's an on-Mac task, not a code task. | 2 h on your Mac |
| Code engine audited | Backend has 155/156 pytest passing but they're synthetic. Real audit is a live-key end-to-end build against a real Anthropic API key. Best done as the **dogfood test** — build Claude Prompt Coach with CodeGenie and see if the swarm holds up. | Loop back after Claude Prompt Coach ships |

Say the word on any of those and I'll ship the code.
