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

## One-time setup (about 10 minutes)

### 1. Turn on Pages

Repository → **Settings → Pages → Build and deployment → Source:
GitHub Actions**.

Not "Deploy from a branch" — the workflow publishes an artifact, which
keeps generated data out of your git history.

### 2. Add the two API keys

Repository → **Settings → Secrets and variables → Actions → New
repository secret**:

| Secret | Where to get it | Cost | Required? |
|---|---|---|---|
| `TMDB_API_KEY` | [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api) — issued instantly | Free | No — falls back to `seed_movies.json` |
| `YOUTUBE_API_KEY` | [console.cloud.google.com](https://console.cloud.google.com) → enable *YouTube Data API v3* → create an API key | Free, 10,000 units/day | No — trailer fields publish as `null` |

Both are optional. With neither, the pipeline still publishes Bluesky
sentiment and Wikipedia velocity for the bundled seed slate.

### 3. Move the workflow to your default branch

**GitHub only fires `schedule` on a repository's default branch.** This
repo's default is `claude/ai-marketplace-ios-app-iUYui`. Until
`.github/workflows/boxcall-data.yml` is merged there, the cron will not
run.

Until then, trigger it by hand: **Actions → BoxCall Data → Run
workflow**.

### 4. Check it published

```
https://<you>.github.io/<repo>/api/v1/index.json
```

You should see a manifest naming each source and how many titles it
covered:

```json
{
  "version": 1,
  "generatedAt": "2026-09-08T12:00:00Z",
  "movieCount": 28,
  "sources": {
    "tmdb": "ok (28 titles)",
    "bluesky": "ok (22/28 titles)",
    "wikipedia": "ok (25/28 titles)",
    "youtube": "ok (8/28 titles)"
  }
}
```

Partial coverage is normal and safe. A source that did not report
publishes `null`, and the client renormalizes around whatever did — an
absent source contributes nothing rather than a fabricated zero.

### 5. Point the app at it

The default in `Config.dataAPIBaseURL` already targets this repo's Pages
site. To use a fork, add `BOXCALL_API_BASE` to `Info.plist`:

```xml
<key>BOXCALL_API_BASE</key>
<string>https://YOURNAME.github.io/YOURREPO/api/v1/</string>
```

The trailing slash matters.

---

## What each source costs

| Source | Auth | Cost | Limit | Used for |
|---|---|---|---|---|
| **Bluesky** | None | Free, no paid tier exists | ~3,000 req / 5 min per IP | 24h mentions + sentiment |
| **Wikipedia** | None | Free | 500 req/hour per IP anonymous | Attention velocity |
| **YouTube** | Free key | Free | 10,000 units/day | Trailer reach + engagement |
| **TMDB** | Free key | Free | Generous | Catalog + posters |
| **GitHub Actions** | — | Free, **unmetered on public repos** | — | Runs the job |
| **GitHub Pages** | — | Free | 100 GB/month, 1 GB site | Serves the JSON |

A run touches roughly 40 titles: ~40 Bluesky searches, ~80 Wikipedia
calls, and — once trailer ids are cached — **one** YouTube call. Eight
runs a day is comfortably inside every limit above.

### Why not X (Twitter)

X **discontinued its free tier in February 2026** and moved to
pay-per-use at **$0.005 per post read**. Reading 500 posts per title
across 40 titles, eight times a day, is about $800/day. There is no
configuration of the X API that is free, so the original `/x-signal`
design was abandoned rather than half-built.

Bluesky's `searchPosts` is the closest free equivalent: public, keyless,
no approval queue, and no paid tier to graduate to.

### Why not Reddit

Reddit's free tier is **non-commercial only** — BoxCall has in-app
subscriptions, so it would not qualify. Commercial access is $0.24 per
1,000 calls, and self-service app registration closed in late 2025 in
favour of a manual approval queue. Not free, not instant.

---

## The YouTube quota, and why it needs care

`search.list` costs **100 units**; `videos.list` costs **1**, regardless
of how many ids it prices. The daily budget is 10,000.

Naively resolving each trailer on every run costs `40 × 100 = 4,000`
units per run — two and a half runs and the day is gone.

So the pipeline:

- resolves each trailer id **at most once** and caches it in the Actions
  cache (a video id never changes),
- caps new searches at **8 per run**, so a cold start spreads its
  resolution over several runs instead of spending the budget at once,
- batches every statistics lookup **50 ids to a request**.

Steady state is **1 unit per run**. Cold start on a 40-title catalog is
about 800 units spread over five runs.

If the key is missing or the quota is spent, trailer fields publish as
`null` and the crowd read simply runs on Bluesky and Wikipedia.

---

## Running it locally

```bash
cd backend/pipeline
pip install -r requirements.txt
python -m pytest tests -q                  # 52 tests, no network needed

export TMDB_API_KEY=...                    # both optional
export YOUTUBE_API_KEY=...
python -m boxcall_pipeline.build --out /tmp/api --max-movies 5
cat /tmp/api/index.json
```

Every network call is wrapped so a failure degrades to `null` rather
than raising — one unlucky title must not take down the build.

---

## Published API

Base: `https://<you>.github.io/<repo>/api/v1/`

| File | Contents |
|---|---|
| `index.json` | Manifest: schema version, build time, per-source coverage |
| `upcoming.json` | The catalog — titles, dates, posters, genres |
| `signals.json` | Per-movie crowd signals, keyed by movie id |

A `signals.json` record:

```json
{
  "id": "tmdb_42",
  "title": "Dune: Part Three",
  "capturedAt": "2026-09-08T12:00:00Z",
  "socialMentions24h": 1843,
  "socialSentiment": 0.42,
  "socialDispersion": 0.31,
  "socialPositive": 61,
  "socialNegative": 14,
  "wikipediaArticle": "Dune: Part Three",
  "wikipediaViews7d": 240113,
  "wikipediaVelocity": 1.34,
  "youtubeViews7d": 12000000,
  "youtubeEngagementRate": 0.031
}
```

**`null` means "not measured", never "zero".** The distinction is
load-bearing throughout — see `SocialSignal.coverage` in the iOS client.
Both sides of this contract are tested: `tests/test_pipeline.py` on the
producer, `BoxCallAPISourceTests.swift` on the consumer.

---

## Sentiment scoring

VADER, a rule-based analyser built for short social text. No model
download, no API call, no GPU — which is what keeps this free.

Stock VADER needed three domain fixes, each covered by a test:

1. **Film slang it does not know.** `flop`, `banger`, `mid`, `cashgrab`,
   `soulless`, `forgettable`, `must-see` and ~40 more carry no valence
   in the general-purpose lexicon.
2. **Discourse hedges scored as praise.** VADER lists `honestly` at
   +2.0 and `pretty` at +2.2, so "honestly it looked mid" and "pretty
   bad" both scored *positive*. Hedges preface criticism at least as
   often as compliments, so this was a systematic upward bias. They are
   neutralized.
3. **Boosters cannot carry an opinion.** `polarity_scores` zeroes any
   token in `BOOSTER_DICT` *before* consulting the lexicon, so
   `incredible` — shipped as a booster — could never score. It is
   released from that dict so it can carry valence.

Posts are weighted by engagement, logarithmically: a post with 900 likes
represents more people than one with none, but a single viral post
cannot own the score.

---

## What is deliberately not built

These need an always-on server, which is the thing that costs money.
None of them block launch:

| Endpoint | Why it is fine to skip |
|---|---|
| `POST /analytics` | Optional telemetry. The client already no-ops when the sink is unreachable. |
| `POST /moderation` | Report/block is local-first today. Needed before user-generated content scales, not before launch. |
| `GET/POST /me` | Accounts are local-first. Cloud sync is a feature, not a dependency. |
| `POST /settlement` | Monday settlement can be published by the same cron as a static file once a Box Office Mojo scraper is added. |

When you do need them, the free options worth trying first are **Hugging
Face Spaces** (Docker, free CPU tier) and **Render** (free web service,
sleeps after 15 minutes of inactivity). `backend/Dockerfile` already
builds the FastAPI app for either.

---

## Troubleshooting

**Workflow does not run on schedule.** It is not on the default branch.
GitHub only fires `schedule` there.

**Pages 404s.** Source is not set to "GitHub Actions", or the first run
has not finished. Check Actions → BoxCall Data.

**`bluesky: ok (0/N titles)`.** Usually genuine — a film months from
release with no marketing has no chatter. If it is 0 across every title,
the runner could not reach `public.api.bsky.app`.

**`youtube: not configured`** with the secret set. The secret must be on
the repository, not an environment, and named exactly
`YOUTUBE_API_KEY`.

**Crowd sentiment looks flat in the app.** Check `index.json` first. If
coverage is good there, the app is probably still inside its 30-minute
document cache or its 3-hour social refresh throttle.
