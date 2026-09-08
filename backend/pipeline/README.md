# BoxCall data pipeline

Builds the static BoxCall API from free, keyless-where-possible sources
and publishes it to GitHub Pages via `.github/workflows/boxcall-data.yml`.

Full setup and cost breakdown: [`../DEPLOY.md`](../DEPLOY.md).

```
boxcall_pipeline/
  sentiment.py        VADER + film-domain lexicon fixes
  build.py            orchestrator; writes index/upcoming/signals JSON
  sources/
    bluesky.py        public search — no key, free (replaces the X API)
    wikipedia.py      pageview velocity — no key, free
    youtube.py        trailer reach — free tier, quota-aware
    tmdb.py           upcoming catalog — free key
tests/                52 tests, no network or keys required
```

Run locally:

```bash
pip install -r requirements.txt
python -m pytest tests -q
python -m boxcall_pipeline.build --out /tmp/api --max-movies 5
```

Every source degrades independently. A source that could not report
publishes `null`, never `0` — the client renormalizes around observed
coverage, so an absent source contributes nothing instead of a
fabricated bearish measurement.
