# Auction Baby — Launch Readiness (what's still needed)

The single punch-list from "code complete" to "live on the App Store." Code
and the automated suites are **done and green**; everything below is testing,
ops, legal, and App Store Connect. Detailed how-to lives in the referenced
docs — this is the tracker.

Status: ✅ done · ☐ to do · 🔴 hard blocker (submission cannot proceed) · ⚠️ risk/decision

Owner key: **You** = founder · **Test** = whoever runs the device · **Legal** = attorney

---

## 0. Already done (baseline — no action)
- ✅ App feature-complete; branch green at latest commit
- ✅ Unit tests 92/92, UI tests 2/2 (iOS 18); XcodeGen project + UI-test target wired
- ✅ iOS 26.1 build compiles; entitlements (Sign in with Apple + Push) committed
- ✅ 4 Cloudflare Workers deployed to **staging**; staging health green
- ✅ APNs configured on the **staging** Auth Worker
- ✅ In-app account deletion, Report & Block, admin moderation/suspend/delete
- ✅ Submission docs written: `APP_STORE_SUBMISSION.md`, `ASC_METADATA.md`,
      `legal/PRIVACY_POLICY.md`, `legal/EULA.md`, `GO_LIVE.md`,
      `QA_CHECKLIST.md`, `DUAL_DEVICE_TEST.md`, `DEPLOY.md`

---

## 1. Testing still needed  → refs: `QA_CHECKLIST.md`, `DUAL_DEVICE_TEST.md`, `GO_LIVE.md`

### Single-device (1 Apple ID — runnable now)  — Owner: Test
- ☐ **Sign in with Apple** end-to-end against the live auth Worker (never yet
      tested — all prior testing was Demo Mode). DOB → role → profile → floor;
      profile syncs; session survives background/relaunch; sign out + back in
- ☐ Money paths on device: gild ladder 750→500→250→0, insufficient-gavel toast,
      **4th-bid paywall**, **StoreKit sandbox purchase** of a Pass + a Gavel pack
- ☐ Woman-side + chat: Summon → accept → match → chat → reactions → Reserve
- ☐ Verification flow, Safety Center, Blocked Users
- ☐ Accessibility: VoiceOver, Dynamic Type (xxxLarge), Reduce Motion, dark mode
- ☐ Performance: Floor scroll at 120 Hz, memory over time

### Current physical-device bundle  — Owner: Test
- ✅ Device-thinned asset compilation completed successfully on the connected
      iPhone 17 Pro Max on 2026-08-10 (the former asset-compilation block is
      cleared)
- ☐ Re-run 92 unit + 2 UI tests with the phone unlocked. The 2026-08-10 run
      built and signed successfully but executed zero tests because Xcode
      stopped at `Unlock iPhone Pro 17 max to Continue`.

### Dual-device (needs a **2nd Apple ID** or 2nd device) 🔴 for cross-device claims
- ☐ Full `DUAL_DEVICE_TEST.md` matrix: discovery → bid → accept → chat →
      whisper-nod → block, refresh-first
- ☐ **Push matrix** on real APNs: each event type → correct device + deep-link,
      foreground vs background-tap, cold launch

---

## 2. Backend / ops  → refs: `DEPLOY.md`, `APP_STORE_SUBMISSION.md`

- 🔴 **Rotate the admin credential** that was previously committed
      (`valasek` / the old password) in the Worker secrets — outstanding since QA
- ☐ Deploy all 4 Workers to **production** (auth, matching, consumables/Stripe,
      profiles) — staging is done; production is not
- ☐ Set **APNs secrets on the production** Auth Worker (3 `wrangler secret put`,
      same as staging) and confirm `/health` → `apns.configured: true`
- ⚠️ **Reserve-the-date kill-switch OFF** for v1.0 review (decision) — and
      **verify the web-Gavel balance-sync path is unconfigured** in the submitted
      build, not merely that its CTA is hidden
- ☐ Point a **Release** `Secrets.xcconfig` at the **production** Worker URLs
- ✅ Fixed the xcconfig `https://` truncation trap in the committed template
      and deployment guide; added `Scripts/release_config_preflight.sh` to
      reject incomplete Release URLs, legal placeholders, or a configured
      consumables/web-Gavel endpoint in the v1 review archive

---

## 3. Legal & hosting 🔴  → refs: `legal/*.md`, `legal/*.html`, `ASC_METADATA.md`

- ✅ Hardened Privacy Policy + EULA drafted (industry-distilled: arbitration +
      class waiver, safety/no-background-check disclaimers, virtual-goods terms,
      CCPA/GDPR rights) — markdown source + **hostable HTML** (`legal/privacy.html`,
      `legal/eula.html`)
- ✅ **Support page** drafted (`legal/support.html`) for the ASC Support URL
- 🔴 **Attorney review + finalize**; fill every `[BRACKET]` (entity name,
      jurisdiction, support/DMCA email, effective date, address, arbitration
      body). Arbitration/class-waiver enforceability varies — counsel must
      confirm.  — Owner: Legal
- 🔴 **Host** the finalized pages at stable public URLs (GitHub Pages /
      Cloudflare Pages — the HTML is ready to drop in)  — Owner: You
- 🔴 **Set `AB_TERMS_URL` / `AB_PRIVACY_URL`** in `Secrets.xcconfig` (and the
      Support URL in ASC) → the paywall links + Settings rows render from these;
      blank = 3.1.2 rejection
- ☐ Verify both links open from: the **paywall**, **Settings**, and the **App
      Store description**

---

## 4. App Store Connect setup  → ref: `APP_STORE_SUBMISSION.md` (all detail)

### Account / agreements 🔴
- 🔴 **Paid Apps agreement** signed; **banking + tax** forms complete (required
      before any IAP can be reviewed)
- ☐ Bundle id `com.valasek.auctionbaby` registered with SIWA + Push capabilities

### App record & metadata
- ☐ Create the app record; category (Lifestyle recommended)
- ☐ Paste metadata from `ASC_METADATA.md`: name, subtitle, promo, description
      (incl. subscription block), keywords, URLs, what's-new
- ☐ **Age rating → 17+** (no real-money gambling flags)
- ☐ **Privacy Nutrition Label** completed to match the Privacy Policy exactly
      (contact info, user content, identifiers incl. push token + linked
      `appAccountToken`, purchases, verification data)
- ☐ **Content Rights = Yes** (production displays user UGC)

### In-app purchases (16 products) 🔴
- 🔴 Create all **16 products**, IDs matching the code exactly (see the doc's
      table): 3 subs, 4 Gavel packs, 1 Boost, 8 status archetypes
- ☐ Subscription **group** "Auction Baby Pass" with the 3 tiers ranked
      (Paddle < Reserve < Black Card), monthly
- ☐ Per-product **display name, description, and a paywall review screenshot**
- ☐ Set consumable/archetype **prices in ASC** (subs + archetype prices come
      from code; **Gavel-pack + Boost prices are yours to set** — the dollar
      figures in the doc are suggestions)
- ⚠️ `status.trillionaire` at **$9,999.99** needs Apple **custom pricing**
- ☐ All products **"Ready to Submit"** and attached to the version

---

## 5. Assets

- ☐ **App icon** — confirm all required sizes present, no alpha channel
      (a heart-paddle icon exists in the project; verify completeness)
- ☐ **Screenshots** — iPhone **6.9"/6.7"** required (3–10): Floor, profile, bid
      composer w/ the date-spend disclosure, match, chat, Pass paywall.
      No nudity / no transactional implication
- ☐ Optional 15–30s app preview video
- ☐ Launch screen renders correctly

---

## 6. Build & submit

- ☐ Bump **version + build number** for each upload (currently `1.0.0` build `2`
      in Info.plist)
- ✅ `ITSAppUsesNonExemptEncryption = false` already in Info.plist (standard TLS
      only) — export-compliance prompt is pre-answered
- ☐ Archive **Release** build → upload (Organizer / Transporter)
- ☐ **Sandbox-test** every IAP (buy / restore / cancel / interrupted) with a
      Sandbox Apple ID
- ☐ Internal **TestFlight** pass on a real device; crash-free
- ☐ Fill **Review Notes** (Demo Mode path from the doc's template) + reviewer contact
- ☐ **Submit for Review**

---

## Critical path (do in this order)

```
Legal finalized + hosted ─┐
Set AB_*_URL             ─┤
Rotate admin credential  ─┼─► Prod Workers + prod APNs ─► Release build at prod
Paid Apps agreement      ─┘        │
                                   ▼
        Single-device + SIWA + sandbox IAP test (1 Apple ID)
                                   │           2nd Apple ID ─► dual-device + push
                                   ▼
     ASC: app record + metadata + 16 IAP + screenshots + nutrition label
                                   ▼
        Archive → TestFlight → sandbox verify → Submit for Review
```

## The hard blockers, in one place (🔴)
1. Admin credential not yet rotated
2. Privacy Policy + EULA — hardened drafts + hostable HTML ready; still need
   **attorney finalize** + **hosting**
3. `AB_TERMS_URL` / `AB_PRIVACY_URL` not set → paywall legal links blank
4. Paid Apps agreement / banking / tax not confirmed
5. The 16 IAP products not yet created in ASC
6. (For cross-device + push claims) no 2nd Apple ID yet

## Decisions you owe (⚠️)
- Reserve-the-date kill-switch OFF for v1.0? (recommended)
- Final store name / subtitle from `ASC_METADATA.md`
- Gavel-pack + Boost prices
- ✅ **$9,999.99 archetype — DECIDED: keep it.** Action: configure Apple
      **custom pricing** for `com.valasek.auctionbaby.status.trillionaire`
      (standard tiers cap at $999.99), and expect extra review scrutiny on a
      four-figure IAP — be ready to justify it as an optional vanity/status good
      (the EULA §9 already frames it that way).

---

**Bottom line:** nothing in the *code* column remains. Everything above is
ops, legal, testing, and store setup — none of it needs a code change unless a
manual/device test surfaces a defect.
