# Auction Baby — Launch Runbook (exact, in order)

Do these **top to bottom**. Each step has a copy-paste example with the app's
**real** values (bundle id `com.valasek.auctionbaby`, real product ids, real
Worker names). Anything you must supply yourself is written as
`<ANGLE_BRACKETS>`; example legal/ops values are labelled **EXAMPLE — replace**.

Legend: 🔴 hard blocker · ⚠️ decision · ✅ verify step
Nothing here needs a code change — it's ops, legal, ASC, and testing.

> Replace `YOUR-SUBDOMAIN` everywhere with your real `*.workers.dev` subdomain
> (see it once with `cd AuctionBaby/auth && npx wrangler deployments list`).

---

## STEP 1 🔴 — Rotate the exposed admin credential

Two things were once in git and must be rotated: the **client** admin hash and
the **Worker** shared secrets.

**1a. Client admin password** (`AuctionBaby/Models/Admin.swift`). The username
`valasek`, the salt `AuctionBaby-Admin-2026`, and the algorithm are all public,
so the hash is only as safe as a strong password. Recompute it:

```sh
# Pick a NEW strong password, then compute HMAC-SHA256(salt, password), base64:
NEWPW='<your-new-strong-admin-password>'
python3 - "$NEWPW" <<'PY'
import sys, hmac, hashlib, base64
pw = sys.argv[1].encode()
salt = b"AuctionBaby-Admin-2026"
print(base64.b64encode(hmac.new(salt, pw, hashlib.sha256).digest()).decode())
PY
```

Paste the output over `expectedHash` in `Admin.swift`:
```swift
private static let expectedHash = "<paste-the-new-base64-hash-here>"
```
Commit that one-line change. The plaintext lives only with you.

**1b. Worker secrets** — regenerate and re-put the two shared secrets on the
**production** auth Worker (and any Worker that shares them):

```sh
cd AuctionBaby/auth
# Generate fresh random secrets:
openssl rand -base64 32        # -> use as APP_SHARED_SECRET
openssl rand -base64 32        # -> use as SESSION_SECRET  (rotating this signs-out all sessions)

npx wrangler secret put APP_SHARED_SECRET      # paste the first value
npx wrangler secret put SESSION_SECRET         # paste the second value
```
Put the **same** `APP_SHARED_SECRET` on every Worker that calls `/push/send`
(matching, consumables) and update the app's `AB_SHARED_SECRET` (Step 6).

---

## STEP 2 🔴 — Finalize + host the legal pages

**2a. Fill every `[BRACKET]`** in `legal/privacy.html`, `legal/eula.html`,
`legal/support.html`. Exact fill-map (these are **EXAMPLES — your attorney
replaces them**; the app already points at the GitHub Pages URLs below):

| Bracket | EXAMPLE value (replace) |
|---|---|
| `[LEGAL ENTITY NAME]` | `Auction Baby, LLC` |
| `[JURISDICTION]` | `State of Delaware, USA` |
| `[ARBITRATION BODY]` | `American Arbitration Association (AAA)` |
| `[ADDRESS]` | `<your registered business address>` |
| `[SUPPORT_EMAIL]` | `support@auctionbaby.app` |
| `[DMCA_EMAIL]` | `dmca@auctionbaby.app` |
| `[EU_REP]` | `<EU/UK representative, if you serve those markets>` |
| `[EFFECTIVE_DATE]` | `2026-08-11` |
| `[YEAR]` | `2026` |
| `[RESPONSE_TIME, e.g., 1–2 business days]` | `1–2 business days` |
| the arbitration `[Insert rules, seat, fees…]` block | counsel drafts — enforceability varies |

> Keep the bracketed markdown/html in git as the master; do the fill on the
> copies you host. 🔴 **Attorney must confirm** the arbitration + class-waiver
> clauses before you publish.

**2b. Host on GitHub Pages** — ✅ **DONE (plumbing).** This repo deploys Pages
from `docs/` via `.github/workflows/deploy-pages.yml` (auto-runs on any push
touching `docs/**` on this branch — no manual Settings → Pages step). The
Auction Baby pages are now published at `docs/auctionbaby/`, which maps to the
exact URLs the app's fallback expects, so even a blank `Secrets.xcconfig`
resolves:

```
https://mvalasek77-droid.github.io/Mike_claw/auctionbaby/privacy.html
https://mvalasek77-droid.github.io/Mike_claw/auctionbaby/terms.html   (= eula.html, links rewritten)
https://mvalasek77-droid.github.io/Mike_claw/auctionbaby/support.html
```

> ⚠️ The root `docs/{privacy,terms,support}.html` are a DIFFERENT app's pages
> (AI Marketplace) — do NOT point Auction Baby at them. Auction Baby lives
> under `docs/auctionbaby/`.
>
> To refresh after the attorney fills the brackets: edit
> `AuctionBaby/legal/*.html`, re-copy into `docs/auctionbaby/`
> (`cp eula.html terms.html` + `sed -i 's/eula\.html/terms.html/g'`), push —
> the Action redeploys to the same URLs.

🔴 **Still blocked on content:** the published pages still contain 21
`[BRACKET]` placeholders (entity, jurisdiction, arbitration body, emails,
dates). They now resolve (no more 404), so the paywall links and screenshot
frame 6 work — but **Apple will reject bracketed legal**, so the attorney
fill (2a) must land before Submit for Review.

✅ After the Action finishes, open all three URLs in a browser — they must
render, not 404.

---

## STEP 3 🔴 — Point the app at the hosted legal URLs

Edit `AuctionBaby/Config/Secrets.xcconfig` (create from
`Secrets.xcconfig.example` if missing). Add exactly:

```
AB_TERMS_URL   = https:/$()/mvalasek77-droid.github.io/Mike_claw/auctionbaby/terms.html
AB_PRIVACY_URL = https:/$()/mvalasek77-droid.github.io/Mike_claw/auctionbaby/privacy.html
```
> The `/$()/` is the xcconfig trick to keep `//` from starting a comment.
> These feed `BackendConfig.termsURL` / `privacyURL` → the paywall + Settings
> links. Blank here = **3.1.2 rejection** and a blank screenshot frame 6.

✅ Build, open the paywall, tap **Terms** and **Privacy** — both must open the
hosted pages.

---

## STEP 4 🔴 — App Store Connect: agreements first

Nothing IAP-related can be reviewed until this is green.

1. ASC → **Business** → **Agreements, Tax, and Banking**.
2. Sign the **Paid Applications** agreement.
3. Complete **Banking** (payout account) and **Tax** forms.
4. ✅ Status for "Paid Apps" shows **Active**.
5. Confirm bundle id `com.valasek.auctionbaby` exists in the Developer portal
   with **Sign in with Apple** + **Push Notifications** capabilities enabled.

---

## STEP 5 🔴 — Deploy Workers to production + prod APNs

All four Workers are on staging; production is not. Deploy each (prod is the
top-level env in each `wrangler.toml`):

```sh
cd AuctionBaby
for w in auth matching consumables backend; do (cd $w && npx wrangler deploy); done
```

Current production resources (provisioned 2026-08-11):

- D1 `auctionbaby-users`: `5ee09895-b80a-4a06-994f-45d45668cd55`
- Consumables KV: `0ed3ab5b5a3d4f059fbf1928801981dd`
- Payout KV: `cd07d62ccc654b28afca193fdc860e2a`
- Worker subdomain: `mvalasek77.workers.dev`
- R2 is disabled at the account level; profile photos use monograms
- Payout cron is disabled until a Cloudflare cron slot is freed or the account
  is upgraded from the Free plan

Then set the **three APNs secrets** on the **production** auth Worker (same as
staging, prod env this time):

```sh
cd AuctionBaby/auth
npx wrangler secret put APNS_AUTH_KEY_P8    # paste the FULL .p8 PEM (BEGIN/END lines included)
npx wrangler secret put APNS_KEY_ID         # 10-char Key ID from Apple Developer → Keys
npx wrangler secret put APNS_TEAM_ID        # 10-char Apple Team ID
```

✅ Verify:
```sh
curl -sS https://auctionbaby-auth.YOUR-SUBDOMAIN.workers.dev/health
# expect: "apns": { "configured": true, ... }, "adminGated": true, "sessionSecretConfigured": true
```
⚠️ **Decision:** keep the **Reserve-the-date kill-switch OFF** for v1.0, and
verify the web-Gavel balance-sync path is unconfigured in the submitted build
(CTA hidden is not enough).

---

## STEP 6 🔴 — Point the app at the production Workers

In the **Release** `Secrets.xcconfig`, set every backend URL to prod + the new
shared secret from Step 1b (real ids shown, sub in your subdomain):

```
AB_AUTH_URL        = https:/$()/auctionbaby-auth.YOUR-SUBDOMAIN.workers.dev
AB_MATCHING_URL    = https:/$()/auctionbaby-matching.YOUR-SUBDOMAIN.workers.dev
# App Store v1: deliberately blank. This is the binary-level kill switch for
# external Gavel syncing and Reserve-the-date checkout.
AB_CONSUMABLES_URL =
AB_WORKER_URL      = https:/$()/auctionbaby-payout.YOUR-SUBDOMAIN.workers.dev
AB_SHARED_SECRET   = <the-new-APP_SHARED_SECRET-from-step-1b>
```
✅ Configured URLs must be the **production** hosts, not `-staging`.
`AB_CONSUMABLES_URL` must remain blank in the v1 review archive; the release
preflight enforces this and the client clears any persisted staging override.

---

## STEP 7 🔴 — Create the 16 IAP products (ids must match the code EXACTLY)

ASC → your app → **Monetization → In-App Purchases** (and **Subscriptions**).
Create all 16 with these **exact** Product IDs. Prices for subs/status come
from code; Gavel + Boost prices are yours to set (suggested).

### Subscriptions — group "Auction Baby Pass", monthly, ranked low→high
| Rank | Product ID | Ref name | Price |
|---|---|---|---|
| 1 | `com.valasek.auctionbaby.sub.paddle` | Paddle | your monthly price |
| 2 | `com.valasek.auctionbaby.sub.reserve` | Reserve | your monthly price |
| 3 | `com.valasek.auctionbaby.sub.blackcard` | Black Card | your monthly price |

### Consumables — Gavel packs
| Product ID | Ref name | Grants | Suggested $ |
|---|---|---|---|
| `com.valasek.auctionbaby.gavels.handful` | Handful of Gavels | 1,000 | $4.99 |
| `com.valasek.auctionbaby.gavels.stack` | Stack of Gavels | 5,000 | $19.99 |
| `com.valasek.auctionbaby.gavels.chest` | Chest of Gavels | 14,000 | $49.99 |
| `com.valasek.auctionbaby.gavels.vault` | Vault of Gavels | 30,000 | $99.99 |

### Consumable — Boost
| Product ID | Ref name | Suggested $ |
|---|---|---|
| `com.valasek.auctionbaby.boost.spotlight` | Spotlight Boost (30 min) | $2.99 |

### Non-consumables — status archetypes (price is fixed by design)
| Product ID | Ref name | Price |
|---|---|---|
| `com.valasek.auctionbaby.status.goodguy` | Good Guy | $4.99 |
| `com.valasek.auctionbaby.status.inandout` | In & Out Guy | $9.99 |
| `com.valasek.auctionbaby.status.whynot` | Why Not Guy | $19.99 |
| `com.valasek.auctionbaby.status.goodjob` | Got a Good Job | $99.99 |
| `com.valasek.auctionbaby.status.inheritance` | Inheritance Money Guy | $999.99 |
| `com.valasek.auctionbaby.status.influencer` | Influencer | $2,499.99 ⚠️ |
| `com.valasek.auctionbaby.status.ferrari` | I Drive a Ferrari | $4,999.99 ⚠️ |
| `com.valasek.auctionbaby.status.trillionaire` | Trillionaire | $9,999.99 ⚠️ |

⚠️ The three marked tiers exceed the $999.99 standard ceiling → request
**custom / high-tier pricing** in ASC (Apple approval, expect extra scrutiny;
justify as an optional vanity/status good — EULA §9 frames it that way).

For **each** product: display name, description, and a **paywall review
screenshot**. Set all 16 to **"Ready to Submit"** and attach to the version.

---

## STEP 8 ✅ — Single-device test (1 Apple ID, runnable now) → `QA_CHECKLIST.md`

- ☐ **Sign in with Apple** end-to-end against the **prod** auth Worker (never
      yet tested — all prior runs were Demo Mode): DOB → role → profile → floor;
      profile syncs; session survives background/relaunch; sign out + back in.
- ☐ Money on device: gild ladder 750→500→250→0, insufficient-gavel toast,
      **4th-bid paywall**, **sandbox purchase** of one Pass + one Gavel pack.
- ☐ Woman side + chat: Summon → accept → match → chat → reactions → Reserve.
- ☐ Verification, Safety Center, Blocked Users.
- ☐ Accessibility: VoiceOver, Dynamic Type xxxLarge, Reduce Motion, dark mode.
- ✅ Physical-device build + full automated suite passed: 96/96 (94 unit +
      2 UI) on iPhone 17 Pro Max / iOS 27.0, 2026-08-10.

---

## STEP 9 ✅ — Dual-device + push (needs a 2nd Apple ID) → `DUAL_DEVICE_TEST.md`

- ☐ Full matrix: discovery → bid → accept → chat → whisper-nod → block,
      refresh-first, across two accounts.
- ☐ **Push matrix on real APNs** — use `push-payloads/` (5 ready files). For
      each of the five event types: correct device + deep-link, foreground vs
      background-tap, cold launch. Send via `POST /push/send` (see
      `push-payloads/README.md`, section B). Sim-only routing check is section A.

---

## STEP 10 ✅ — ASC app record, metadata, assets → `ASC_METADATA.md`, `SCREENSHOTS.md`

- ☐ Create the app record; category **Lifestyle**.
- ☐ Paste name/subtitle/promo/description (incl. the subscription block),
      keywords, URLs, what's-new from `ASC_METADATA.md`.
- ☐ Support URL = the hosted `support.html`.
- ☐ **Age rating → 17+** (no real-money gambling flags).
- ☐ **Privacy Nutrition Label** — match the Privacy Policy exactly (contact
      info, user content, identifiers incl. push token + linked
      `appAccountToken`, purchases, verification data).
- ☐ **Content Rights = Yes** (app shows user UGC).
- ☐ **Screenshots** 6.9"/6.7" per `SCREENSHOTS.md`. Frame 3 must show the
      date-spend disclosure; frame 6 must show price + /month + benefits +
      Restore + **rendered** Terms/Privacy links (needs Step 3 done first).
- ☐ App icon: all sizes, no alpha. Launch screen renders.

---

## STEP 11 ✅ — Build, TestFlight, submit

- ✅ Bumped submission candidate to version `1.0.0`, build `3`.
- ✅ `ITSAppUsesNonExemptEncryption = false` already set (export prompt pre-answered).
- ☐ Archive **Release** (prod config) → upload via Organizer/Transporter.
- ☐ **Sandbox-test every IAP**: buy / restore / cancel / interrupted, with a
      Sandbox Apple ID — all 16 products.
- ☐ Internal **TestFlight** pass on a real device; crash-free.
- ☐ **Review Notes**: Demo Mode path (name = `demo`) from
      `APP_STORE_SUBMISSION.md`; reviewer contact.
- ☐ **Submit for Review.**

---

## Dependency order (why this sequence)

```
1 admin rotate ─┐
2 legal host ───┼─► 3 set AB_*_URL ─┐
4 paid-apps ────┘                   │
5 prod Workers + APNs ──────────────┼─► 6 app→prod URLs ─► 7 create 16 IAP
                                    │
                                    ▼
        8 single-device + SIWA + sandbox IAP  (1 Apple ID)
                                    │        2nd Apple ID ─► 9 dual-device + push
                                    ▼
        10 ASC record + metadata + nutrition + screenshots
                                    ▼
        11 archive → TestFlight → sandbox verify → Submit
```

**Blocked-on-you gates (🔴):** 1 admin, 2 legal (attorney), 4 paid-apps, 7 IAP,
and a 2nd Apple ID for 9. Everything else you can do today.
