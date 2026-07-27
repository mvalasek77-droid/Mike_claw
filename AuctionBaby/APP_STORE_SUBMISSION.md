# Auction Baby — App Store Connect Submission Guide

A field-by-field walkthrough of the entire App Store Connect (ASC) submission,
with the exact values to paste, every in-app purchase, the paywall mapping, and
the reviewer demo-mode steps. Work top to bottom — later sections can't be
completed until the earlier ones exist.

> Apple moves the ASC UI around from time to time; section **names** here match
> what you'll see, even if the exact page layout shifts. Anything in a
> `code box` is meant to be pasted verbatim.

---

## 0. Prerequisites (do these first, they gate everything)

- [ ] **Apple Developer Program** membership active ($99/yr), signed in at
      [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
- [ ] **Agreements, Tax, and Banking** → the **Paid Apps Agreement** shows
      **Active**, with a bank account + tax forms complete. *Until this is
      Active you cannot create or test any in-app purchase.*
- [ ] Bundle ID `com.valasek.auctionbaby` registered (Certificates, IDs &
      Profiles → Identifiers) — Xcode usually creates it on first upload
- [ ] The app builds and archives from Xcode on a Mac (Phase 0 of
      `LAUNCH_CHECKLIST.md`)

---

## 1. Create the app record

**My Apps → ➕ → New App**

| Field | Value |
|---|---|
| Platforms | **iOS** |
| Name | `Auction Baby` |
| Primary language | `English (U.S.)` |
| Bundle ID | `com.valasek.auctionbaby` |
| SKU | `auctionbaby-ios-01` (any unique internal string) |
| User Access | Full Access |

> **Name collision:** if "Auction Baby" is taken, ASC rejects it here. Have a
> backup (e.g. "Auction Baby: Bid to Date") ready; the name is also what
> reviewers judge against the concept.

---

## 2. App Information (left sidebar → *General → App Information*)

| Field | Value |
|---|---|
| Subtitle | `Bid for the date. Earn it.` (30 char max) |
| Category → Primary | **Social Networking** |
| Category → Secondary | **Lifestyle** |
| Content Rights | Check **"Contains, shows, or accesses third-party content"** = **No** (all content is original/simulated) |
| Age Rating | Set via the questionnaire → see **§8**. Target: **17+** |

There is no "description" here — that lives on the version page (**§5**).

---

## 3. Pricing and Availability

| Field | Value |
|---|---|
| Price (the app itself) | **Free** (Tier 0) — revenue is all IAP |
| Availability | All countries/regions, or restrict as you like |
| Pre-orders | Off for v1 |

> The app being **Free** is important: everything monetized is an in-app
> purchase or the external real-world reservation fee. Do not set an app price.

---

## 4. In-App Purchases & Subscriptions — "the paywall parts"

This is the biggest section. You are recreating, **exactly**, the catalog in
`Products.storekit`. **Product IDs must be character-identical** or the app
shows no products. Left sidebar → **Monetization → In-App Purchases** and
**Monetization → Subscriptions**.

### 4a. ⚠️ Request high price points FIRST (do this before creating IAPs)

Three status products are above Apple's default $999.99 ceiling. Apple grants
higher price points case-by-case and **reviews the request**, so start it early:

**ASC → Business → (Agreements) → request access to price points above
$999.99** (up to Apple's absolute max of **$9,999.99**). Without this you
literally cannot create Influencer, Ferrari, or Trillionaire.

### 4b. Consumables (Monetization → In-App Purchases → ➕ → Consumable)

| Reference Name | Product ID | Price |
|---|---|---|
| Handful of Gavels | `com.valasek.auctionbaby.gavels.handful` | $4.99 |
| Stack of Gavels | `com.valasek.auctionbaby.gavels.stack` | $19.99 |
| Chest of Gavels | `com.valasek.auctionbaby.gavels.chest` | $49.99 |
| Vault of Gavels | `com.valasek.auctionbaby.gavels.vault` | $99.99 |
| Spotlight Boost | `com.valasek.auctionbaby.boost.spotlight` | $3.99 |

### 4c. Non-consumables — the 8 status ratings (➕ → Non-Consumable)

| Reference Name | Product ID | Price |
|---|---|---|
| Good Guy | `com.valasek.auctionbaby.status.goodguy` | $4.99 |
| In & Out Guy | `com.valasek.auctionbaby.status.inandout` | $9.99 |
| Why Not Guy | `com.valasek.auctionbaby.status.whynot` | $19.99 |
| Got a Good Job | `com.valasek.auctionbaby.status.goodjob` | $99.99 |
| Inheritance Money Guy | `com.valasek.auctionbaby.status.inheritance` | $999.99 |
| Influencer | `com.valasek.auctionbaby.status.influencer` | $2,499.99 ⚠️ |
| I Drive a Ferrari | `com.valasek.auctionbaby.status.ferrari` | $4,999.99 ⚠️ |
| Trillionaire | `com.valasek.auctionbaby.status.trillionaire` | $9,999.99 ⚠️ |

⚠️ = needs the §4a high-price-point grant first.

### 4d. Subscriptions — Auction Baby Pass (Monetization → Subscriptions)

Create **one Subscription Group** named `Auction Baby Pass`. All three tiers go
in it (so a user can up/downgrade within the group):

| Reference Name | Product ID | Duration | Price |
|---|---|---|---|
| Paddle | `com.valasek.auctionbaby.sub.paddle` | 1 month | $19.99 |
| Reserve | `com.valasek.auctionbaby.sub.reserve` | 1 month | $39.99 |
| Black Card | `com.valasek.auctionbaby.sub.blackcard` | 1 month | $99.99 |

### 4e. For EACH in-app purchase and subscription, fill these sub-fields

ASC won't let you submit an IAP until every one of these is done:

- **Reference Name** — internal only (table above)
- **Product ID** — from the tables (immutable once saved — triple-check)
- **Price** — pick the exact tier
- **Localization (English U.S.)** — a **Display Name** and **Description**
  shown on the App Store / in system purchase sheets. Suggested copy:
  - *Gavel packs:* Display "Stack of Gavels", Desc "5,000 Gavels to gild bids,
    insure bids, and freeze streaks."
  - *Boost:* "Spotlight Boost" / "30 minutes at the top of the floor."
  - *Status:* "Trillionaire" / "The rarest status rating. What you pay is the
    signal — worn openly on the floor, owned forever."
  - *Subs:* "Black Card" / "Top Pass tier: see if you're the top bid, unlimited
    bids, read receipts, priority placement, auto-rebid."
- **Review Screenshot** — a 1290×2796 (or any valid iPhone size) screenshot of
  the paywall/store screen where that product appears. Take these from the
  build running the `demo` account (§7).
- **Review Notes (per product)** — for the status ratings, paste:
  > "Status ratings are non-consumables. The premise of the app is that the
  > rating a man wears IS what he paid for it — the price is the product, not an
  > arbitrary charge. Gavels (consumables) never buy status."
- **Subscription extras:** set the **Subscription Duration**, a **Group Display
  Name** (`Auction Baby Pass`), and localized benefit copy per tier. Add the
  **Terms of Use (EULA)** + **Privacy Policy** links (Apple shows these on the
  paywall — required).

### 4f. Paywall → product mapping (so screenshots + notes match the app)

| In-app surface | Products shown |
|---|---|
| **Store tab** (hammer icon) → Gavel packs | the 4 `gavels.*` consumables |
| Store → Spotlight Boost | `boost.spotlight` |
| **Paywall** (`PaywallView`) — Pass upsell | the 3 `sub.*` subscriptions |
| **Status tab** (`ArchetypeStoreView`) | the 8 `status.*` non-consumables |
| Bid composer "Gild" / "Bid Insurance" | *no IAP* — spent in Gavels |

### 4g. ⚠️ The "Reserve the date" fee is NOT an in-app purchase

Do **not** create an IAP for it. It's a **real-world booking fee** collected via
**Stripe** (Apple guideline 3.1.3(e)/3.1.5: real-world services between two
people must not use IAP). You don't configure it in ASC at all — but you **must
explain it in App Review notes** (§7) so a reviewer who sees an external payment
sheet understands why it's allowed. It has a server-side kill-switch if Apple
still objects.

---

## 5. The version page (1.0 → Prepare for Submission)

### 5a. Screenshots (required)
- [ ] **6.9"** (iPhone 16 Pro Max, 1320×2868) — required set
- [ ] **6.5"** (older Pro Max, 1284×2778) — recommended
- Capture 3–8 shots running the `demo` account: the floor, a profile with the
  bid composer, the store, the status tab, a match/chat, the credit report.

### 5b. Text fields (paste from `APP_STORE.md`)

**Promotional Text** (170 char, editable without resubmit):
```
Find a high value man, find out what you're worth. Men bid what a date is worth; she accepts when the number's right. Reputation is everything.
```

**Description** — paste the full block from `APP_STORE.md` §Description.

**Keywords** (100 char, comma-separated, no spaces):
```
dating,auction,bid,match,singles,date,chat,relationship,verified,luxury,premium,meet,love,flirt
```

**Support URL:** `https://auctionbaby.app/support` (must resolve)
**Marketing URL:** `https://auctionbaby.app` (optional)

**What's New** (first release):
```
Welcome to the floor. Place your first bid, build your reputation, and find out what you're worth.
```

**Copyright:** `2026 Michael Valasek` (or your legal entity)

### 5c. Build
- [ ] Attach the build uploaded from Xcode / TestFlight (§9)

---

## 6. App Privacy (nutrition labels)

Left sidebar → **App Privacy → Get Started**. Answer from `APP_STORE.md`
§Privacy. This build is client-local for consumers:

| Question | Answer |
|---|---|
| Do you collect data? | **Yes** (purchases go through Apple) |
| **Data used to Track You** | **None** |
| **Data Linked to You** | **None** |
| **Data Not Linked to You** | **Purchases** (via Apple) + an anonymous `appAccountToken` (per-install UUID, no PII, used only so a refund routes to the right wallet) |
| Third-party analytics/ads SDKs | **None** |

> If/when a production build adds real accounts (name, photos, ID verification),
> update the labels to add those under "Data Linked to You → App Functionality,
> not for tracking." The current build doesn't.

---

## 7. App Review Information — **where reviewer demo mode goes**

Left sidebar → version page → **App Review Information**.

| Field | Value |
|---|---|
| Sign-in required? | **No** (the app needs no account) |
| Contact — First/Last | Michael Valasek |
| Phone / Email | your real contact |
| Demo account | Not needed — but explain the credential in Notes ↓ |

**Notes to App Review** — paste this whole block:

```
This app has a credential-driven Demo Mode for review (no login system exists).

HOW TO ENTER DEMO MODE:
1. Launch the app. On the onboarding screen, choose EITHER role
   ("Bid on dates" = the man side is the most feature-rich).
2. In the NAME field, type:  demo   (case-insensitive)
3. Leave everything else default and tap "Step onto the floor."

That exact name activates Demo Mode for the session:
- Wallet pre-funded with 25,000 Gavels (+ free demo top-ups)
- All 8 status ratings marked owned (equip free; real buy buttons stay live
  for sandbox verification)
- Auction Baby Pass can be activated free from any paywall ("Demo: activate")
- "Reserve the date" can be exercised free ("Demo: reserve free")
No password, email, or payment method is required.

ABOUT THE MONEY MODEL:
- Bids are shown in dollars but are LETTERS OF INTENT — no charge is made in
  the app for any bid, including the "$1,000,000 Masterpiece." Date payment is
  a real-world, person-to-person matter settled off-platform. The app never
  collects, holds, or transmits it (no escrow / money transmission).
- The 8 status RATINGS are genuine non-consumable IAPs; the price is the
  product (the premise is that what a man pays for his rating is the signal).
- "Reserve the date" is a small REAL-WORLD BOOKING FEE (tiers $10–$100)
  collected via Stripe, NOT IAP, per guideline 3.1.3(e)/3.1.5 (a real-world
  service between two people). It is kept by the platform, never paid to the
  other user, and unlocks no in-app content — the app only marks the date
  "reserved." It has a server-side kill-switch.
- "Copycat" profiles are AI-generated and disclosed to users at onboarding;
  the app never takes money on a Copycat interaction.

A Products.storekit config is bundled so all IAPs load in the simulator.
See DEMO_MODE.md in the repository for a 12-minute reviewer walkthrough.
```

---

## 8. Age Rating questionnaire (target 17+)

App Information → Age Rating → **Edit**. Answer honestly toward a **17+**
result (mature/suggestive dating themes):

- Sexual Content or Nudity → **Infrequent/Mild** (suggestive themes, no nudity)
- Mature/Suggestive Themes → **Frequent/Intense** (it's a dating app)
- Simulated Gambling / Contests → **None** (bids are not gambling; be ready to
  clarify in notes — no wager, no chance-based payout)
- Alcohol/Tobacco/Drug references → **Infrequent/Mild** (lifestyle prompts)
- Unrestricted Web Access → **No**
- Everything else → **None**

Result should compute to **17+**. If it lands lower, that's fine as long as it's
honest, but 17+ suits the concept.

---

## 9. Build upload + TestFlight (before you can submit)

- [ ] Xcode → Product → **Archive** → Distribute App → App Store Connect →
      Upload
- [ ] Wait for processing (email), then it appears under **TestFlight** and is
      selectable on the version page
- [ ] **Export Compliance:** already handled — `Info.plist` sets
      `ITSAppUsesNonExemptEncryption = false` (the app uses only standard
      data-protection encryption, which is exempt), so ASC won't ask each build
- [ ] Internal TestFlight to yourself; sandbox-test a Gavel pack, a Boost, a
      Pass, a status rating, and a refund (`LAUNCH_CHECKLIST.md` Phase 4)

---

## 10. Final submission checklist (the "Submit for Review" gate)

ASC blocks submission until all are green:

- [ ] Screenshots (at least the 6.9" set)
- [ ] Promotional text, Description, Keywords, Support URL
- [ ] Build attached
- [ ] **All 16 IAPs "Ready to Submit"** and, for the first release, **attached
      to this version** (scroll to the *In-App Purchases* box on the version
      page and add them, or they won't review together)
- [ ] App Privacy complete
- [ ] Age Rating set
- [ ] App Review notes (§7) pasted
- [ ] Content Rights + Export Compliance answered
- [ ] **Advertising Identifier (IDFA):** answer **No** (the app uses no IDFA)

Then **Add for Review → Submit**.

---

## 11. Known review-risk hot spots for THIS app (be ready)

1. **The concept** ("men bid on dates"). Lead reviewers to the disclosures:
   bids are letters of intent, no money is transmitted, the woman is never paid
   through the app. Emphasize it's entertainment + reputation, not escort/
   transactional sex. (If they read it as facilitating prostitution it's an
   instant reject — the notes in §7 pre-empt this.)
2. **The $9,999.99 Trillionaire IAP.** Expect a hard look. Your defense: it's a
   non-consumable status badge, the price *is* the product, and it can't be
   "laundered" through consumables (Gavels never buy status). Requesting the
   high price point (§4a) with a clear justification is half the battle.
3. **The Stripe "Reserve the date" fee.** If flagged as "circumventing IAP,"
   respond that it is a real-world service (an in-person date reservation),
   which guideline 3.1.3(e)/3.1.5 requires be handled off-IAP; it unlocks no
   digital content. If they still object, flip `RESERVE_ENABLED="false"` on the
   Worker (no app update) and resubmit.
4. **AI "Copycat" profiles.** FTC-sensitive. Your defense: disclosed at
   onboarding, revealed immediately after a bid, and no money is ever taken on
   a Copycat interaction.
5. **Gambling read.** Bids have no wager and no chance-based payout — clarify in
   notes if the age-rating "contests" question draws a question.

---

## Quick reference — the demo credential

> **Onboarding → any role → Name = `demo` → Step onto the floor.**
> No password. Seeds 25,000 Gavels, marks all status owned, and enables the free
> demo buttons for Pass and Reserve. Reset via Profile → Reset account.
