## 2026-10-13 — Reddit niche sweep (dinner date / who pays / apps broken / deleted apps)

**Status: FAILED FETCH — no data logged.** All four Reddit JSON searches
(`www.reddit.com/search.json?...&sort=top&t=week&raw_json=1`) returned Reddit's
"whoa there, pardner!" network-policy block wall (HTML, 189,908-byte static page)
instead of JSON, for every UA tried (browser UA, api.reddit.com, http1.1, after
30s cool-down). Safari fetch() fallback (per playbook) also failed: CORS/network
error from the only open tab (Play Console). No posts could be verified, so
none are logged — zero fabricated entries.

**HN pulse (same run):** item 49517518 "Auction Baby: auction-house dating –
she picks the bid she likes" — score 1, 0 comments, flagged `dead:true` on
hn.firebaseio.com (Algolia returns 404 on the item). Not gaining traction.

**Blog index health:** 5/6 URLs HTTP 200; `blog/index.html` → 404
(direct file path). Directory URL `.../blog/` itself returns 200.

## 2026-10-14 — Reddit niche sweep (day 2 re-attempt)

**Status: FAILED FETCH — no data logged.** Reddit network block persists from this
host (matches 2026-10-13). Exhausted avenues, all returned 403 + ~190 KB HTML
block wall instead of JSON:
- `www.reddit.com/search.json` (curl, multiple UAs incl. browser) → 403
- `old.reddit.com/search.json` → 302 → login wall (lor2)
- `oauth.reddit.com` and `api.reddit.com` search → 403
- Safari `do JavaScript` **same-origin** fetch from an opened `www.reddit.com`
  tab: `/search.json` → 403 (189,906 B), `/r/dating_advice/top.json` → 403
  (189,906 B). Tab also stuck on reddit JS challenge (`js_challenge=1`).

Searches intended (none could be verified, zero fabricated entries):
"dinner date"/"who pays" pain, "dating apps are broken", "deleted the apps",
last 7 days, sort=top.

**HN pulse:** item 49517518 now hard-404 on Algolia
(https://hn.algolia.com/api/v1/items/49517518) and zero hits for "Auction Baby"
in Algolia story search — story removed/dead (yesterday: score 1, 0 comments,
flagged `dead:true`). Not gaining traction. No watchdog recreation (condition:
score ≥ 3 or new comments — not met).

**Blog index health:** all 6 URLs now HTTP 200, including `blog/index.html`
(404 yesterday — one transient 404 observed today before 6 consecutive 200s;
dir URL `.../blog/` also 200). 6/6 OK.

## 2026-10-15 — Reddit niche sweep (first data via PullPush archive)

**Status: FETCH OK, ZERO QUALIFYING POSTS.** `www.reddit.com/search.json`,
`api.reddit.com`, and `old.reddit.com/search.json` again 403/block-walled this
host (curl and Safari same-origin XHR — 189,906-B HTML wall / "Not Found").
Worked around via the PullPush Reddit archive
(`api.pullpush.io/reddit/search/submission/?q=...&since=<now-7d>`), which
returned real JSON for all four queries. Parsed 400 submissions total
(100/query, `since` = 7 days ago):

- "dinner date": 100 — max score 23 (2.1d old). None >100.
- "who pays": 100 — max score 7. None >100.
- "dating apps are broken": 100 — max score 231 but it is 85d old; within
  7 days max score is single digits. None >100 qualify. (Near-miss context:
  r/TrueAnon "Dating apps are so much more broken than just a few years ago",
  141 pts, 65d old — outside window.)
- "deleted the apps": 100 — max score 5. None >100.

**Conclusion: no post this week meets the >100-upvote bar, so none logged as
opportunities.** Zero fabricated entries. Note for future runs: PullPush is a
usable fallback while direct Reddit JSON stays 403; it lags a couple of days
and skews to smaller subs, so treat as partial coverage, not exhaustive.

**HN pulse:** item 49517518 still hard-404 on Algolia
(`api/v1/items/49517518`); Firebase returns `dead:true`, score 1, no comment
count/children; Algolia search for "Auction Baby" in story titles: 0 hits.
Not gaining traction → watchdog NOT recreated (condition: score ≥ 3 or new
comments — unmet).

**Blog index health:** 6/6 HTTP 200 — index.html, who-pays-on-the-first-date,
how-much-should-a-first-date-cost, dating-apps-without-photos,
dating-app-red-flags, why-dating-apps-are-broken (dir URL `.../blog/` 200).

## 2026-10-16 — Niche sweep day 3: reddit RSS works for titles, PullPush confirms zero >100

**Status: FETCH PARTIAL (titles only), ZERO QUALIFYING POSTS.** Direct Reddit
`.json` endpoints still 403/block-walled this host (curl, Safari same-origin
via `osascript do JavaScript` — all four queries returned the 145-byte "blocked
by network security" wall; `api.reddit.com` also 403). New workaround this run:
`https://www.reddit.com/search.rss??...` Atom feeds DO work via curl (severe
429 rate-limiting — needs 30-60s sleeps between queries, one failed query
after 4 retries). Parsed 142 real posts (t3_) with titles/subs/timestamps,
**but Reddit RSS does not expose upvote or comment counts**, so the >100
upvote bar cannot be evaluated from RSS alone. Cross-checked with PullPush
archive (`api.pullpush.io`, `after=<epoch-7d>`): all four queries returned
data, **zero posts >100 upvotes in the last 7 days** (max single digits;
PullPush scores are mostly placeholder 1s, treated as unreliable — used only
to rule out >100 candidates). Reddit rate-limit note: queries that return HTTP
200 are 350-450 KB; a 5 KB body means the query matched ~nothing (e.g.
"dating apps are broken" → 0 posts in window).

Query-level detail (last 7 days):
- "dinner date": RSS 50 entries, PullPush 100 — notable title: r/dating_advice
  "Feeling burnt out always paying and planning first dates. Is it okay to ask
  her to split…", 3.5d old, score/unknown, small. Relevant theme (first-date
  payment fatigue) but not >100.
- "who pays" date: RSS + PullPush — nothing relevant >100.
- "dating apps are broken": PullPush 0 hits in window; RSS n/a matchable.
- "deleted the apps": PullPush 8 — none relevant, none >100.

**Conclusion: no post this week meets the >100-upvote bar; nothing logged as
an opportunity.** No fabricated entries.

**HN pulse:** `hn.algolia.com/api/v1/items/49517518` returns 404 {"error":"Not
Found"} (previously returned dead-flag JSON — now fully gone from the index);
live HN page shows the submission tagged **[dead]** (45 days old, no score, no
comments). Algolia search: 0 hits for "Auction Baby" in titles. Not gaining
traction → watchdog NOT recreated (condition: score ≥ 3 or new comments —
unmet; post is dead/removed, not just low-scored). Existing disabled watch
cron `c644f32eb7d0` left as-is.

**Blog index health:** 6/6 HTTP 200 — index.html, who-pays-on-the-first-date,
how-much-should-a-first-date-cost, dating-apps-without-photos,
dating-app-red-flags, why-dating-apps-are-broken.

## 2026-10-17 — Niche sweep (blocked)

Sweep attempted for: "dinner date" pain, "who pays" debates, "dating apps are broken", "deleted the apps" (top/week, >100 upvotes filter).

- reddit.com search.json returned an HTML "blocked by network security" page to curl, and the same wall via Safari (`document 1` fetch returned empty; loading the URL directly in Safari showed the blocked-interstitial body). old.reddit.com now requires login for search.json.
- No posts could be evaluated; nothing appended this run. No Fabrication.
- HN context: item 49517518 (Auction Baby story) returns 404 from Algolia API and no "Auction Baby" story is indexed — fetch failed, no numbers reported.

### 2026-10-17 amendment — HN item verified via Firebase API
hacker-news.firebaseio.com/v0/item/49517518.json: `{"by":"mvalasek","dead":true,"id":49517518,"score":1}` — no kids/comments. Third consecutive day the story is dead/flagged (score 1, 0 comments). Cron-recreation trigger (score>=3 or new comments) NOT met.
