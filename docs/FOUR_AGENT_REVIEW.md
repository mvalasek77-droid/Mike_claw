# Four-Agent Review Synthesis

Output from four parallel agents auditing the v0.2.2 codebase:

1. **Task-by-task verifier** — does the code actually do what the UX promises?
2. **Spelling & grammar** — copy quality across all user-facing strings
3. **Simplification audit** — where is the front more complicated than the brief allows?
4. **Competitive critique** — CodeGenie vs App-of-Year winners, Codex, Cursor, Claude Code

This document captures **what was fixed in code** and **what remains as product decisions for you**.

---

## Fixed in code (PR: claude/four-agent-fixes)

### Real bugs

1. **Terms scroll-to-bottom gate was bypassable**
   Sentinel used `.onAppear`, which fires the moment the view enters the hierarchy — not when the user actually scrolls. Replaced with a `GeometryReader` + `PreferenceKey` that only flips the flag when the sentinel's frame intersects the visible window.

2. **App Store Connect walkthrough buttons advertised actions they didn't perform**
   Step buttons said "Upload icon", "Auto-fill this step", "Open on my Mac" — but tapping them only marked the step complete. Renamed every step button to "Mark step done" and added a "macbook" prefix line explaining what the user actually has to do on their Mac. Honest > broken-promise.

### Grammar fixes

| File | Was | Now |
|---|---|---|
| `HomeView.swift:347` | "App of Year gates" | "App of the Year gates" |
| `HomeView.swift:430` | "what to open once" (dangling) | "how to install it, and what to open it for" |
| `BuildScreen.swift:618` | "Build green" (jargon) | "Build complete" |
| `BuildScreen.swift:66` | "does not hurt the build" | "doesn't hurt the build" |
| `FirstBuildPromptView.swift:31` | "Sending it to the App Store needs..." (passive) | "To send it to the App Store, you'll need..." |

### Simplification wins

- **DescribeAppView**: `categoryPicker` + `stylePicker` collapse behind a single `customizeDisclosure` ("Customize (optional) · Productivity · Liquid Glass"). 95% of users keep defaults; they no longer have to scan past two horizontal scrollers.
- **BuildScreen success overlay**: was 8 stacked CTAs at the moment of celebration. Now two primary buttons (Open simulator preview · Submit to App Store) and a "More actions" disclosure for GitHub backup + workspace download.

---

## Remaining product decisions

These are bigger asks. They need **your** call before I make them — they change product direction, not just code quality.

### From the simplification agent

| # | Recommendation | Pro | Con |
|---|---|---|---|
| 1 | **Cut onboarding from 8 → 5 slides.** Drop Icon (slide 6) and Pricing (slide 7) since they're post-build knowledge. | Faster time-to-home. Less to read. | You explicitly asked for pricing surface in onboarding (#0.2.0). Pricing slide is a recent intentional add. |
| 2 | **Collapse BuildScreen top bar from 7 icons to 3 + "Build tools" menu.** | Calmer mid-build experience. | Power users currently use snapshots and pause mid-build frequently. Hiding them adds a tap. |
| 3 | **Hide ship readiness card from daily HomeView after first build.** | Stops nagware feel. | Users with partial setup might forget. |
| 4 | **Auto-collapse 3 of 4 ship rows; show only the next blocker.** | Less visual noise. | Removes the "see the path" mental model. |

### From the competitive critic (4.2/10 App-of-Year score)

The brutal headline: **craft 8/10, instant value 2/10, friction 2/10**. To move toward App-of-Year:

| # | Recommendation | What it would take |
|---|---|---|
| 1 | **Kill the shipping checklist from HomeView's daily home.** | Move it into post-onboarding flow + just-in-time prompts when relevant. |
| 2 | **Ship a runnable on-device sample app in <30 seconds.** | Pre-bake a TideTimes / HabitTracker app, boot it in the iPhone simulator, no backend. The current "Try a sample" plays a video. |
| 3 | **Move App Store submission onto the phone, or remove the promise.** | Either wire ASC API direct from iOS, or label the feature "v0.3 — needs your Mac". The current path dumps users into Mac Safari. |

### From the task verifier

| # | Surface | Issue |
|---|---|---|
| 1 | DescribeAppView cost confirmation | Shows the **tier** ($/Pro/Studio) but not the actual estimated $ for THIS build. Verifier suggests adding a per-build estimate (e.g. "≈ $0.15 with Sonnet"). |
| 2 | ASC walkthrough | Even after the copy fix, the underlying experience is still "go do this on your Mac". Either implement direct ASC API calls (months of work) or move this entire flow to the Mac Companion app where it belongs. |

---

## Recommended order of operations

If you only do three things, do these:

1. **Make "Try a sample" actually run on-device.** Biggest leverage on App-of-Year metrics — flips instant value from 2 → 7.
2. **Decide on the shipping checklist's home.** Either keep it on HomeView (current) or move it to a separate "Setup" tab. Both audit agents flagged it independently.
3. **Decide what to do about ASC submission.** Either wire it properly through the iOS app, or honestly label it as a Mac-required step in the success overlay.

Items 4-N from the agents are polish that pays off after the above three.

---

## Scoreboard (post-fixes)

| Axis | Pre-fixes (competitive agent) | Estimated post-fixes |
|---|---|---|
| Calm utility | 3/10 | 4-5/10 (success overlay decluttered) |
| Instant value | 2/10 | unchanged (needs sample-app work) |
| Surprising delight | 6/10 | unchanged |
| Native craft | 8/10 | 8-9/10 (Terms bug fixed, copy tightened) |
| No friction | 2/10 | unchanged (still 12+ taps to finished build) |

The code-only fixes in this PR move calm utility and native craft. Friction and instant value require the bigger product decisions above.
