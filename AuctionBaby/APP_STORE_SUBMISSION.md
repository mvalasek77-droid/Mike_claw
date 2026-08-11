# Auction Baby — App Store Submission Guide

Two parts: **Part 1** is the App Store Connect (ASC) submission checklist;
**Part 2** is the paywall / in-app-purchase submission (the subscription
review, Guideline 3.1.2). Read the **Review-risk callouts** first — this app
has three areas Apple will scrutinize, and getting them wrong is the most
likely rejection.

Bundle id: `com.valasek.auctionbaby` · Age rating: **17+** · Sign in with
Apple, Push, StoreKit subscriptions + consumables + non-consumables.

Legend: ☐ to do · ✅ done · ⚠️ risk

---

## ⚠️ Read first — the three things that get this app rejected

1. **The concept (men bidding on women).** Guideline 1.1 (objectionable) /
   1.1.4. The defense is baked into the copy and *must stay consistent* in the
   App Store description and screenshots: a bid is a **letter of intent — the
   money a man commits to spend on the date itself (dinner, drinks, the
   night), never a payment to her.** The app never moves money between users
   (enforced in code). Do **not** use language in metadata that implies buying
   a person, escorting, or transactional sex. Frame it as a **dating app with
   an auction-house theme where intent is signalled by planned generosity.**

2. **"Reserve the date" Stripe booking fee (external payment).** Guideline
   3.1.1 requires IAP for digital content. Reserve charges a **real-world
   booking fee via Stripe** and *unlocks nothing in the app* — it's the
   real-world-service exception. Apple may still challenge it. **Recommendation
   for v1.0 submission: ship with the Reserve kill-switch OFF** (the remote
   flag hides the live checkout fleet-wide). Do not turn it on immediately
   after approval; submit the exact payment behavior for review later and be
   ready to explain the real-world service, fulfiller, and refund terms.

3. **UGC moderation (Guideline 1.2).** A dating app with user profiles/photos/
   chat MUST have: content you can filter, a **report + block** mechanism,
   published contact info, a commitment to **act on reports within 24h and
   eject abusive users**, and an **EULA with a zero-tolerance clause** for
   objectionable content. The app has report/block, admin moderation, and
   suspend/delete — surface all of it in the review notes.

Also: **do not mention, link to, hint at, or grant balances from the external
web Gavel shop inside the submitted iOS configuration.** In-app Gavels are
digital goods and must be sold through IAP absent an applicable regional rule
or entitlement. The code contains a web-balance synchronization path, so verify
that path is unconfigured—not merely that its CTA is hidden.

---

# Part 1 — App Store Connect submission checklist

## A. Prerequisites
- ☐ Apple Developer Program membership active ($99/yr, paid)
- ☐ Bundle id `com.valasek.auctionbaby` registered (Identifiers), with
      **Sign in with Apple** + **Push Notifications** capabilities enabled
- ☐ APNs Auth Key (.p8) created (same one set on the Auth Worker)
- ☐ **Paid Apps agreement** signed in ASC → Business (required for any IAP)
- ☐ Banking + tax forms complete (Agreements, Tax, and Banking)

## B. App record
- ☐ New app in ASC: name **"Auction Baby"** (or your final store name — check
      availability), primary language, bundle id, SKU
- ☐ Primary category: **Lifestyle** or **Social Networking** (dating apps
      typically Lifestyle; Social Networking triggers extra UGC scrutiny —
      Lifestyle is the safer pick)
- ☐ Secondary category: optional

## C. Metadata (App Information + Version)
- ☐ **Name** (30 char), **Subtitle** (30 char)
- ☐ **Promotional text** (170 char, updatable without review)
- ☐ **Description** — must include, per 3.1.2, the subscription facts (see
      Part 2 §D) and must keep the compliant framing from the risk callout
- ☐ **Keywords** (100 char) — avoid trademarked/again-avoid transactional terms
- ☐ **Support URL** (required, must resolve)
- ☐ **Marketing URL** (optional)
- ☐ **Terms of Use (EULA) URL** and **Privacy Policy URL** — the same ones set
      in `Secrets.xcconfig` (`AB_TERMS_URL` / `AB_PRIVACY_URL`); Privacy Policy
      is a required ASC field
- ☐ **Content Rights:** answer **Yes** for the production app when it displays
      user-uploaded profiles/photos or other UGC, and confirm you have the
      necessary rights and moderation process. Answer No only for a genuinely
      local/simulated build containing solely owned or licensed assets.
- ☐ **Copyright**, **Version** string matching `CFBundleShortVersionString`

## D. Screenshots & preview
- ☐ **iPhone 6.9"** (or 6.7") — **required**; upload 3–10
- ☐ iPhone 6.5" — recommended
- ☐ iPad 12.9" — only if the app supports iPad
- ☐ Optional app preview video (15–30s)
- ⚠️ Screenshots must reflect real UI and the compliant framing; no nudity,
      no implied transactional content. Show: the Floor, a profile, the bid
      composer with the "money you'll spend on the date" disclosure, a match,
      chat, the Pass paywall.

## E. Age rating
- ☐ Complete the questionnaire → **17+**
      (Mature/Suggestive Themes: Frequent/Intense; Simulated Gambling: None —
      the "auction" is not gambling; Sexual Content and Nudity: None if you
      keep it clean; Unrestricted Web Access: No)
- ⚠️ Do **not** enable anything that reads as real-money gambling — the bid is
      not a wager.

## F. App Privacy (the Nutrition Label)
Complete **App Privacy → Data collection** truthfully. Likely declarations:
- ☐ **Contact Info**: name, email (via Sign in with Apple relay) — linked to
      identity, used for app functionality
- ☐ **User Content**: photos, bio/prompts, messages — app functionality
- ☐ **Identifiers**: user id, device token (push) — app functionality
- ☐ **Purchases**: purchase history — app functionality
- ☐ **Usage/Diagnostics**: only if you actually collect analytics/crash data
      (be honest; the app uses an on-device ErrorMonitor — declare only what
      leaves the device)
- ☐ **Verification data and sensitive/profile attributes**: declare anything
      the configured verification service or Workers receive or retain
- ☐ Treat `appAccountToken` as linked when a backend uses it to route a wallet
      or refund; a UUID is not automatically "Data Not Linked to You"
- ☐ Inventory every production processor and log sink: Apple/StoreKit, Sign in
      with Apple, push delivery, photo storage/CDN, verification, Stripe (if
      present), and Worker/server logs
- ☐ Confirm the label matches the Privacy Policy exactly
- ☐ **Account deletion** is in-app (Settings → Delete Account) — required since
      2022 for any account-creation app ✅ (already built)

## G. Sign in with Apple compliance
- ☐ SIWA present ✅. If you offer any other third-party login, SIWA must be
      offered too (currently SIWA is the only server login — compliant)
- ☐ Never request Apple's private-relay email be replaced; never require the
      user to disable Hide My Email

## H. Build, capabilities, export compliance
- ☐ Archive a **Release** build; version + build number incremented
- ☐ Capabilities in the archived build: Sign in with Apple, Push (aps-environment
      = production for the store build) ✅ entitlements committed
- ☐ Upload via Xcode Organizer or `xcrun altool`/Transporter
- ☐ **Export compliance**: the app uses only standard HTTPS/TLS → answer the
      encryption question accordingly; add `ITSAppUsesNonExemptEncryption = false`
      to Info.plist if that's true to skip the prompt each upload
- ☐ Build appears in ASC → TestFlight; run **internal TestFlight** first

## I. Review information
- ☐ **Sign-in required?** Yes → provide the **Demo Mode** path in notes (see §K)
- ☐ **Contact** name, phone, email for the reviewer
- ☐ **Notes** (see §K) — this is where you defuse the three risks
- ☐ Attachments: optional screen recording of the Demo flow

## J. Pricing & availability
- ☐ App is **free** (monetization is via IAP)
- ☐ Territories: choose (consider excluding regions where the concept is
      legally sensitive)
- ☐ No pre-order unless intended

## K. Review notes template (paste into "Notes")
```
Auction Baby is a dating app with an auction-house theme. A "bid" is a
LETTER OF INTENT — the money a man commits to spend ON THE DATE ITSELF
(dinner, drinks, the evening). It is never a payment to another user; the
app has no mechanism to transfer money between users, by design.

REVIEW ACCESS — no real account needed:
1. On the first screen, choose a role (Bidder or Lot).
2. In the name field, type: demo
   ("demo" activates Demo Mode: play-money, fictional profiles, and every
   paid feature is unlocked for review with no charge — including the full
   Auction Baby Pass and Gavel economy.)
3. Complete onboarding to reach the main floor.
   - Bidders: browse, place bids, open the Pass paywall.
   - Lots: use "Summon a bidder" to populate the inbox, accept/decline,
     open the match + chat.

SAFETY / UGC (Guideline 1.2): every profile and chat has Report & Block
(removes the user from your floor and blocks contact). Reports are reviewed;
abusive users are suspended/deleted. Account deletion is in Settings.

SUBSCRIPTIONS: "Auction Baby Pass" (Paddle / Reserve / Black Card, monthly,
auto-renewable) unlocks bidder features. Terms + Privacy are linked on the
paywall and in Settings. Restore Purchases is on the paywall.

RESERVE CHECKOUT: the production Reserve checkout is disabled for this
submission. Demo Mode may mark a fictional date reserved without payment so
the reviewer can inspect the state. No external checkout or digital
entitlement is offered by that demo action.
```

---

# Part 2 — Paywall / IAP submission (Guideline 3.1.2)

## A. Products to create in ASC (Features → In-App Purchases / Subscriptions)

**Auto-renewable subscriptions** — one **Subscription Group** ("Auction Baby
Pass"), three tiers, each **monthly**:
| Tier | Product ID | Price |
|---|---|---|
| Paddle | `com.valasek.auctionbaby.sub.paddle` | $19.99 |
| Reserve | `com.valasek.auctionbaby.sub.reserve` | $39.99 |
| Black Card | `com.valasek.auctionbaby.sub.blackcard` | $99.99 |

**Consumables:**
| Product | Product ID | Grants |
|---|---|---|
| Gavels — Handful | `com.valasek.auctionbaby.gavels.handful` | 1,000 · $4.99 |
| Gavels — Stack | `com.valasek.auctionbaby.gavels.stack` | 5,000 · $19.99 |
| Gavels — Chest | `com.valasek.auctionbaby.gavels.chest` | 14,000 · $49.99 |
| Gavels — Vault | `com.valasek.auctionbaby.gavels.vault` | 30,000 · $99.99 |
| Spotlight Boost | `com.valasek.auctionbaby.boost.spotlight` | 30 min top placement · $3.99 |

**Non-consumable status archetypes:**
| Product | Product ID | Price |
|---|---|---|
| Good Guy | `com.valasek.auctionbaby.status.goodguy` | $4.99 |
| In & Out Guy | `com.valasek.auctionbaby.status.inandout` | $9.99 |
| Why Not Guy | `com.valasek.auctionbaby.status.whynot` | $19.99 |
| Got a Good Job | `com.valasek.auctionbaby.status.goodjob` | $99.99 |
| Inheritance Money Guy | `com.valasek.auctionbaby.status.inheritance` | $999.99 |
| Influencer | `com.valasek.auctionbaby.status.influencer` | $2,499.99 |
| I Drive a Ferrari | `com.valasek.auctionbaby.status.ferrari` | $4,999.99 |
| Trillionaire | `com.valasek.auctionbaby.status.trillionaire` | $9,999.99 |

⚠️ Prices above $999.99 require Apple's custom pricing and draw extra scrutiny.
Confirm you want these prices and be ready to justify them as status/vanity
goods—not services.

- ☐ Every product: reviewed state must be **"Ready to Submit"** and attached
      to **this app version** (subscriptions can be submitted with the build)
- ☐ Product IDs must **exactly** match `StoreKitService.swift`

## B. Subscription group configuration
- ☐ Group display name (localized): "Auction Baby Pass"
- ☐ Rank the three tiers (Paddle < Reserve < Black Card) so upgrades/downgrades
      resolve correctly
- ☐ Set a subscription duration (monthly) per tier
- ☐ (Optional) intro offers / free trial — if used, the paywall must disclose
      the trial length + post-trial price

## C. Per-product metadata (each subscription)
- ☐ **Display name** + **Description** (what it unlocks)
- ☐ **Review screenshot** — a screenshot of the **in-app paywall** showing that
      product (required; reviewers reject subs with a missing/again-wrong shot)
- ☐ At least one **localization**
- ☐ Price / duration set

## D. In-app paywall requirements (must be visible in the binary)
Apple requires ALL of these on the paywall — the app's `PaywallView` already
implements them; verify before submit:
- ✅ Subscription **name/title** (Paddle / Reserve / Black Card)
- ✅ **Length** ("/ month")
- ✅ **Price** (from StoreKit `displayPrice`)
- ✅ **What's included** (benefits matrix)
- ✅ **Functional Terms (EULA) + Privacy Policy links** — sourced from
      `BackendConfig`. The code currently falls back to hosted GitHub Pages
      URLs when `AB_TERMS_URL` / `AB_PRIVACY_URL` are blank. Prefer explicit
      HTTPS Release values and verify both public pages on a clean device; they
      must describe the real production data flows and deletion behavior.
- ✅ **Restore Purchases** (toolbar)
- ✅ **Auto-renew disclosure** ("Auto-renews monthly until canceled at least
      24h before the period ends. Billed to your Apple ID; manage in Settings.")
- ☐ Confirm the same disclosure text also appears in the **App Store
      description** (3.1.2 requires it in metadata too)

## E. App description subscription block (paste near the end of the description)
```
Auction Baby Pass is an auto-renewable subscription.
• Paddle — $19.99/month · Reserve — $39.99/month · Black Card — $99.99/month
• Payment is charged to your Apple ID at confirmation of purchase.
• The subscription auto-renews unless canceled at least 24 hours before the
  end of the current period. Your account is charged for renewal within 24
  hours prior to the end of the current period.
• Manage or cancel in your Apple ID account settings after purchase.
• Terms of Use: <AB_TERMS_URL>   Privacy Policy: <AB_PRIVACY_URL>
```

## F. Consumables & non-consumables — review notes
- ☐ Note that **Gavels** are in-app currency for **status only** (Gilded Bids,
      Bid Insurance, streak freezes) — never a payment to another user, never
      cash out
- ☐ Note that **status archetypes** are one-time cosmetic/status purchases
- ☐ In Demo Mode, all of these are granted free so the reviewer can exercise
      them without a sandbox charge

## G. StoreKit testing before you submit
- ☐ Local: run the bundled `Products.storekit` config → verify buy / restore /
      cancel / interrupted purchase for a sub, a Gavel pack, a Boost, an
      archetype
- ☐ **Sandbox**: create a Sandbox Apple ID (ASC → Users and Access → Sandbox),
      sign into it on the device (Settings → Developer or the purchase sheet),
      and run each real purchase against sandbox
- ☐ Verify **Restore Purchases** returns the subscription entitlement
- ☐ Verify a refund/revocation claws back Gavels (StoreKit already handles this)

## H. Common IAP rejection reasons — and how Auction Baby answers them
| Rejection | Status |
|---|---|
| Paywall missing Terms/Privacy links | ✅ present — **set the URLs** |
| Paywall missing price/length/restore | ✅ all present |
| Sub facts missing from App description | ☐ add §E block |
| Missing subscription review screenshot | ☐ attach the paywall shot |
| Steering to external/web purchase | ⚠️ keep the web Gavel shop invisible in-app |
| External payment for digital content | ⚠️ Reserve-the-date — kill-switch OFF for v1.0 |
| Product IDs mismatch binary | ✅ verify against StoreKitService |

---

## Final pre-submit gate
- ☐ Part 1 A–K complete
- ☐ `AB_TERMS_URL` / `AB_PRIVACY_URL` set, both pages live, linked in paywall +
      Settings + App description
- ☐ Admin credential commitment **and** Worker/admin secrets rotated
- ☐ Reserve-the-date kill-switch verified OFF from a clean production install
- ☐ Web Gavel shop not referenced and its iOS balance-grant path unconfigured
- ☐ UGC report/block → moderator queue → action tested against production
- ☐ In-app account deletion tested against production, not Demo Mode alone
- ☐ All IAP products "Ready to Submit" and attached to the version
- ☐ Demo Mode verified by a fresh reviewer walk-through
- ☐ Age rating 17+; Privacy Nutrition Label matches Privacy Policy
- ☐ Release build archived, uploaded, tested via TestFlight, then **Submit for
      Review**
