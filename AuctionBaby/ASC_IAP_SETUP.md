# App Store Connect — IAP & Paywall Setup (step-by-step, for-dummies)

Do this in order. Every product's exact **Product ID**, **price**, **display
name**, and **description** is copy-paste below. IDs must match the app
**character-for-character** or the product won't load.

- ASC = App Store Connect (appstoreconnect.apple.com)
- "Reference Name" = internal, ASC-only (users never see it)
- "Display Name" = what the buyer sees on the purchase sheet
- 🔴 = blocked until done · ✅ = check

---

## PART 0 — Before any IAP will work  🔴

1. ASC → **Business** → **Agreements, Tax, and Banking**.
2. Sign the **Paid Applications** agreement. Complete **Banking** + **Tax**.
3. Wait until "Paid Apps" shows **Active**. *(Until this is Active, every buy
   button in the app is dead and products return empty — this is the #1 cause of
   "nothing loads.")*
4. ASC → your app **Auction Baby** must already exist (bundle id
   `com.valasek.auctionbaby`). If not, create the app record first.

---

## PART 1 — Subscriptions (the "Auction Baby Pass")

### 1A. Create the subscription group  (do this ONCE)
1. ASC → your app → left sidebar **Monetization → Subscriptions**.
2. Click **Create** next to "Subscription Groups".
3. **Reference Name:** `Auction Baby Pass`  → Create.
4. You'll set a **Group Display Name** (shown in the iPhone Manage-Subscriptions
   screen) when it asks for localization: use `Auction Baby Pass`.

### 1B. Create the 3 subscriptions (inside that group)
For **each** row below: in the group, click **Create** (a subscription) → fill
Reference Name + Product ID → set **Duration = 1 Month** → **Subscription
Prices** (Add → pick USD price → Next → Confirm) → add a **Localization**
(English U.S.) with the Display Name + Description → add **App Store Review**
screenshot + notes → **Save**.

| Field | Paddle | Reserve | Black Card |
|---|---|---|---|
| Reference Name | `Pass Paddle` | `Pass Reserve` | `Pass Black Card` |
| **Product ID** | `com.valasek.auctionbaby.sub.paddle` | `com.valasek.auctionbaby.sub.reserve` | `com.valasek.auctionbaby.sub.blackcard` |
| Duration | 1 Month | 1 Month | 1 Month |
| **Price (USD)** | **$19.99** | **$39.99** | **$99.99** |
| Display Name | `Auction Baby Pass — Paddle` | `Auction Baby Pass — Reserve` | `Auction Baby Pass — Black Card` |

**Descriptions (copy-paste into the Localization "Description"):**
- **Paddle:** `Unlimited live bids, see if you're the top bid, and 1 Spotlight Boost every week. Auto-renews monthly until canceled.`
- **Reserve:** `Everything in Paddle, plus reveal her reserve price, auto-rebid to stay on top, advanced filters, and rewind your last bid. Auto-renews monthly until canceled.`
- **Black Card:** `Everything in Reserve, plus priority placement in every inbox and read receipts. Auto-renews monthly until canceled.`

### 1C. Rank the group (upgrade/downgrade order)  ✅
1. Back on the **subscription group** page, find **Subscription Ranking** (drag to order).
2. Order **top → bottom = highest → lowest value**:
   1. Black Card
   2. Reserve
   3. Paddle
   *(This lets Reserve→Black Card be an upgrade, etc. Wrong order = billing quirks.)*

### 1D. Each subscription needs (or it stays "Missing Metadata"):  ✅
- ☐ A **price**
- ☐ One **Localization** (Display Name + Description above)
- ☐ A **review screenshot** (see PART 5)
- ☐ Status flips to **"Ready to Submit"**

> Free trial / intro offer: the app doesn't require one. Skip "Introductory
> Offers" unless you want to add a trial later.

---

## PART 2 — Gavel packs (Consumables ×4)

ASC → **Monetization → In-App Purchases** → **Create** → Type = **Consumable**.
For each: Reference Name + Product ID → **Price** → **Localization** (Display
Name + Description) → **review screenshot** → Save.

| Field | Handful | Stack | Chest | Vault |
|---|---|---|---|---|
| Reference Name | `Gavels Handful` | `Gavels Stack` | `Gavels Chest` | `Gavels Vault` |
| **Product ID** | `com.valasek.auctionbaby.gavels.handful` | `com.valasek.auctionbaby.gavels.stack` | `com.valasek.auctionbaby.gavels.chest` | `com.valasek.auctionbaby.gavels.vault` |
| **Price** | **$4.99** | **$19.99** | **$49.99** | **$99.99** |
| Display Name | `Handful of Gavels` | `Stack of Gavels` | `Chest of Gavels` | `Vault of Gavels` |

**Descriptions:**
- Handful: `1,000 Gavels — in-app currency for status features like Gilded Bids and Bid Insurance.`
- Stack: `5,000 Gavels — in-app currency for status features. Better value than the Handful.`
- Chest: `14,000 Gavels — a deep reserve of in-app status currency.`
- Vault: `30,000 Gavels — the best value pack of in-app status currency.`

> The Gavel **amount** (1,000 / 5,000 / …) is set in the app's code, NOT ASC.
> ASC only needs the price + name + screenshot.

---

## PART 3 — Spotlight Boost (Consumable ×1)

Same steps, Type = **Consumable**.
| Field | Value |
|---|---|
| Reference Name | `Boost Spotlight` |
| **Product ID** | `com.valasek.auctionbaby.boost.spotlight` |
| **Price** | **$4.99** |
| Display Name | `Spotlight Boost` |
| Description | `30 minutes at the top of the floor so more people see your profile.` |

---

## PART 4 — Status archetypes (Non-Consumables ×8)

ASC → **In-App Purchases** → **Create** → Type = **Non-Consumable**. Same field
pattern. These are optional cosmetic/status badges.

| Reference Name | Product ID | Price | Display Name |
|---|---|---|---|
| `Status Good Guy` | `com.valasek.auctionbaby.status.goodguy` | **$4.99** | `Good Guy` |
| `Status In and Out` | `com.valasek.auctionbaby.status.inandout` | **$9.99** | `In & Out Guy` |
| `Status Why Not` | `com.valasek.auctionbaby.status.whynot` | **$19.99** | `Why Not Guy` |
| `Status Good Job` | `com.valasek.auctionbaby.status.goodjob` | **$99.99** | `Got a Good Job` |
| `Status Inheritance` | `com.valasek.auctionbaby.status.inheritance` | **$999.99** | `Inheritance Money Guy` |
| `Status Influencer` | `com.valasek.auctionbaby.status.influencer` | **$2,499.99** ⚠️ | `Influencer` |
| `Status Ferrari` | `com.valasek.auctionbaby.status.ferrari` | **$4,999.99** ⚠️ | `I Drive a Ferrari` |
| `Status Trillionaire` | `com.valasek.auctionbaby.status.trillionaire` | **$9,999.99** ⚠️ | `Trillionaire` |

**Description template (copy, swap the last line per tier):**
`An optional status badge worn on your Auction Baby profile. Cosmetic status only — no gameplay advantage is sold. "<flavor line>"`

Flavor lines:
- Good Guy: `Texts back. Probably splits the bill.`
- In & Out Guy: `Efficient. Knows what he wants.`
- Why Not Guy: `The shrug that launched a thousand dates.`
- Got a Good Job: `Salaried, LinkedIn-verified energy.`
- Inheritance Money Guy: `Didn't earn it. Will absolutely spend it.`
- Influencer: `Will film the date. You signed nothing.`
- I Drive a Ferrari: `The car is leased. The flex is real.`
- Trillionaire: `The whole floor turns.`

⚠️ **The three over $999.99** (Influencer, Ferrari, Trillionaire): when you open
the **Price** picker, scroll to the higher price points (Apple's ceiling is
**$9,999.99**). If a price isn't listed, use **"Plan a price"/custom price
selection**. Expect **extra review scrutiny** on the four-figure ones — the
description above (optional cosmetic, no advantage sold) is your justification.

---

## PART 5 — Review screenshots (required on EVERY product)  🔴

Apple requires **one screenshot per IAP** showing where it appears in the app.
Without it, the product is stuck in **Missing Metadata**. You may **reuse one
image across products on the same screen**, so all 16 need only **4 captures**.

### Setup (do once, so prices actually render)  ✅
Store prices come from StoreKit, so you must run with the local config:
1. Xcode → run the app **from Xcode** (⌘R) on the **iPhone 16/17 Pro Max**
   simulator — this injects `Products.storekit` so real prices show.
   *(The paywall also has fallback prices, but the Gavel/Boost/Status stores go
   blank without the config — so run from Xcode.)*
2. Onboard with the name **`demo`** → Demo Mode populates the floor and lets you
   reach everything without a real account.
3. (Optional, clean status bar) `xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --cellularBars 4`.
4. Capture: `⌘S` in Simulator, or `xcrun simctl io booted screenshot ~/Desktop/shot.png`.

### The 4 captures → which products they cover

| Capture | Role | How to reach it | Must show | Covers |
|---|---|---|---|---|
| **1 · Paywall** | Man (`demo`) | **My Bids → Upgrade** | 3 tiers, each **title + price + "/ month"**, benefits matrix, **Restore**, auto-renew line, **Terms + Privacy** links | the **3 subscriptions** |
| **2 · Gavel store** | Man | Floor → tap the **Gavel counter** (top-right) → Store | the 4 packs with **prices** + the "+X% / BEST VALUE" badges | the **4 Gavel packs** |
| **3 · Status store** | Man | **Status** tab (crown) | the archetype badges with **prices** | the **8 archetypes** |
| **4 · Boost** | Woman | onboard as a **woman** → **You → Settings → Store** | the **Spotlight Boost** with its price | the **1 Boost** |

> Note the role split: Gavels + Passes are **man-side**; the **Boost lives on the
> woman side** (a lot boosting to the top of the floor). So capture 4 needs a
> woman account — reset (Settings → Reset account) and onboard as a woman, name
> `demo`, then You → Settings → Store.

### Upload
Under each product's **App Store Information → Review Screenshot**, upload the
matching capture: #1 on all 3 subs, #2 on all 4 Gavel packs, #3 on all 8
archetypes, #4 on the Boost. Any resolution is fine for review screenshots
(they're not the marketing screenshots).

> Per-tier option: if you'd rather show each specific product, capture the
> paywall three times with each tier selected (its benefits highlight), and the
> Status store scrolled to each badge. Not required — one image per screen is
> accepted.

---

## PART 6 — Attach to the version + submit  ✅

1. Set every product's status to **"Ready to Submit"** (green).
2. ASC → your app → the **1.0 version** page → scroll to **In-App Purchases**
   (or the subscription section) → **add/attach** all 16 so they submit *with*
   the build. *(New apps: the first IAPs must be submitted alongside the app
   version, or they won't go live.)*
3. In **App Review Information → Notes**, tell the reviewer how to test without
   paying: `Demo Mode — onboard with the name "demo" to unlock a free "Demo:
   activate <tier>" button on the paywall and free status, no purchase.`

---

## PART 7 — The App Store description block (Guideline 3.1.2)  ✅

In the version's **Description** (App Information), the subscription facts must
also appear as text. Paste this near the bottom:

```
Auction Baby Pass is an auto-renewable subscription.
• Paddle — $19.99/month
• Reserve — $39.99/month
• Black Card — $99.99/month
Payment is charged to your Apple ID at confirmation. It renews automatically
unless canceled at least 24 hours before the period ends. Manage or cancel in
Settings → Apple ID → Subscriptions.
Terms of Use: <your terms URL>   Privacy Policy: <your privacy URL>
```
Also set the **App Store → App Information → License Agreement** (or use Apple's
standard EULA) and the **Privacy Policy URL**.

---

## PART 8 — Common mistakes (check these if something's off)
- ❌ **Product ID typo** → product silently never loads. Copy-paste, don't type.
- ❌ **Paid Apps agreement not Active** → *all* products empty.
- ❌ **No review screenshot** → stuck "Missing Metadata," can't submit.
- ❌ **Subscriptions not ranked** → upgrade/downgrade billing acts weird.
- ❌ **Wrong product Type** (e.g., Gavels as Non-Consumable) → can't re-buy;
  Gavels/Boost = **Consumable**, badges = **Non-Consumable**, Pass = **Auto-Renewable**.
- ❌ **IAPs not attached to the version** (new app) → they don't go live with 1.0.
- ❌ Testing purchases on a **non-Xcode device install** with no sandbox account →
  see `SANDBOX_IAP_TESTING.md`.

---

## The 16 products at a glance
| # | Type | Product ID | Price |
|---|---|---|---|
| 1 | Auto-renew | `...sub.paddle` | $19.99/mo |
| 2 | Auto-renew | `...sub.reserve` | $39.99/mo |
| 3 | Auto-renew | `...sub.blackcard` | $99.99/mo |
| 4 | Consumable | `...gavels.handful` | $4.99 |
| 5 | Consumable | `...gavels.stack` | $19.99 |
| 6 | Consumable | `...gavels.chest` | $49.99 |
| 7 | Consumable | `...gavels.vault` | $99.99 |
| 8 | Consumable | `...boost.spotlight` | $4.99 |
| 9 | Non-Consumable | `...status.goodguy` | $4.99 |
| 10 | Non-Consumable | `...status.inandout` | $9.99 |
| 11 | Non-Consumable | `...status.whynot` | $19.99 |
| 12 | Non-Consumable | `...status.goodjob` | $99.99 |
| 13 | Non-Consumable | `...status.inheritance` | $999.99 |
| 14 | Non-Consumable | `...status.influencer` | $2,499.99 |
| 15 | Non-Consumable | `...status.ferrari` | $4,999.99 |
| 16 | Non-Consumable | `...status.trillionaire` | $9,999.99 |

(All IDs are prefixed `com.valasek.auctionbaby`.)
