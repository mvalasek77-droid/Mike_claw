# Getting BoxCall online for free

The backend is a **scheduled job that publishes static JSON**, not a
server. That is the whole trick: there is nothing running to pay for.

```
GitHub Actions (cron, every 3h)          GitHub Pages (CDN)
  ├─ Bluesky      public API, no key  ──┐
  ├─ Wikipedia    REST API,   no key  ──┤
  ├─ YouTube      free tier,  key     ──┼──►  site/api/v1/*.json  ──► iOS app
  └─ TMDB         free tier,  key     ──┘
```

Running cost: **$0/month**, permanently, with no trial that expires and
no card on file.

---

## ⚠️ Where it actually runs (read this first)

**The pipeline deploys from the dedicated repo
[mvalasek77-droid/boxcall-data](https://github.com/mvalasek77-droid/boxcall-data),
NOT from this monorepo.**

Live API: `https://mvalasek77-droid.github.io/boxcall-data/api/v1/`

Why not here:

1. **GitHub only fires `schedule` on a repository's default branch.**
   This monorepo's default is `claude/ai-marketplace-ios-app-iUYui`,
   so a workflow checked into `pr-30` would never run on cron — which
   is exactly how the app shipped with an API that had never published
   a single `actuals.json`.
2. **This monorepo's GitHub Pages is deployed by another project**
   (`deploy-pages.yml` serves the AI Marketplace landing). A second
   Pages-publishing workflow would clobber that site every 3 hours.

`backend/pipeline/` here remains the **development home** of the
pipeline: edit it, test it (`python -m pytest tests -q`), then mirror
the changed files into `boxcall-data` and push. The two copies are
kept in sync manually; both suites must stay green.

The app side is already pointed at the live URL — see
`Config.dataAPIBaseURL` in `BoxCall/Services/SocialSignalSources.swift`.

---

## Why this shape

The read endpoints are the ones that matter — the app needs a catalog,
crowd sentiment, and tracking numbers. All of them are the *same answer
for every user*, refreshed a few times a day. That is a static file, and
a static file on a CDN is free, infinitely scalable, and has no cold
start.

The original FastAPI skeleton in `backend/app` is kept for the write
endpoints (analytics, moderation, account sync). None of those are
needed for the app to function, and each one is what would force a paid
always-on host, so they are deliberately not deployed. See
[What is deliberately not built](#what-is-deliberately-not-built).

---

## How opening-weekend actuals are published

Settlement is the one payload where a wrong number costs real (play)
money, so `actuals.json` is never single-sourced:

1. **Cross-checked chart read** — Box Office Mojo's weekend chart AND
   The Numbers' weekend chart must both report the film as a NEW
   release with figures agreeing within 2%. Disagreement publishes
   nothing; the settlement holds and the next run re-checks.
2. **Corroborated release-page read** — BOM's per-release "Opening"
   figure must agree with the chart read when both exist.

Both sites' un-dated "current" pages are **calendar indexes, not
charts**; the fetchers compute the latest weekend's dated URL
(BOM `/weekend/{year}W{week}/`, TN `/box-office-chart/weekend/{date}`).

Holdover guard: a film's second-weekend gross must never be recorded as
its opening. BOM rows carry a weeks-in-release column (opening ⇔ 1),
TN rows carry a `(new)` marker, and the collector only considers films
released within the last 10 days.

Known actuals for the shipped seed slate are also pinned client-side in
`SettlementService.knownActuals` (e.g. Resident Evil 2026W38 = $60.0M)
so a fresh install settles correctly even before its first API fetch.

---

## One-time setup (already done for boxcall-data)

1. **Turn on Pages**: Settings → Pages → Source: **GitHub Actions**
   (not "Deploy from a branch").
2. Secrets (optional): `TMDB_API_KEY`, `YOUTUBE_API_KEY` — with neither,
   the pipeline still publishes sentiment, Wikipedia velocity, and
   box-office actuals.

---

## Running it locally

```bash
cd backend/pipeline
pip install -r requirements.txt
python -m pytest tests -q                  # 62 tests, no network needed

export TMDB_API_KEY=...                    # both optional
export YOUTUBE_API_KEY=...
python -m boxcall_pipeline.build --out /tmp/api --max-movies 12
cat /tmp/api/actuals.json
```

Every network call is wrapped so a failure degrades to `null` rather
than raising — one unlucky title must not take down the build.

---

## Published API

Base: `https://mvalasek77-droid.github.io/boxcall-data/api/v1/`

| File | Contents |
|---|---|
| `index.json` | Manifest: schema version, build time, per-source coverage |
| `upcoming.json` | The catalog — titles, dates, posters, genres |
| `signals.json` | Per-movie crowd signals, keyed by movie id |
| `actuals.json` | Cross-checked opening-weekend actuals for settlement |

**`null` means "not measured", never "zero".** The distinction is
load-bearing throughout — see `SocialSignal.coverage` in the iOS client.
Both sides of this contract are tested: `tests/test_pipeline.py` on the
producer, `BoxCallAPISourceTests.swift` on the consumer.

---

## Troubleshooting

**Workflow does not run on schedule.** It must be on the repository's
default branch. In this monorepo it never will be — that's why the
pipeline lives in `boxcall-data`.

**`actuals.json` is empty for a film that opened.** Either the two
charts disagree (by design, nothing publishes), or the film is outside
the 10-day window. Check the run log's `boxoffice:` source status.

**Pages 404s.** Source is not set to "GitHub Actions", or the first run
has not finished. Check the repo's Actions tab.

**`bluesky: ok (0/N titles)`.** Usually genuine — a film months from
release with no marketing has no chatter. If it is 0 across every title,
the runner could not reach `public.api.bsky.app`.