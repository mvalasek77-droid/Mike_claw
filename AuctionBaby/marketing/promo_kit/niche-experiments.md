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
