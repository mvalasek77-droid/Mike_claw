# Sandbox IAP Testing — full paywall + Gavel store

How to actually **buy** every in-app purchase and verify the money paths, two
ways: a **local StoreKit config** you can run in minutes with no Apple setup,
and the **real App Store Sandbox** for the pre-submission pass. Do Route A
first (fast, functional), then Route B (proper, required before you ship).

Legend: ✅ do · 🔴 blocker · 💰 money-safety check

---

## The products under test (IDs must match everywhere)

**Subscriptions (auto-renewable, group "Auction Baby Pass"):**
```
com.valasek.auctionbaby.sub.paddle
com.valasek.auctionbaby.sub.reserve
com.valasek.auctionbaby.sub.blackcard
```
**Consumables (Gavel packs + Boost):**
```
com.valasek.auctionbaby.gavels.handful   → 1,000
com.valasek.auctionbaby.gavels.stack     → 5,000
com.valasek.auctionbaby.gavels.chest     → 14,000
com.valasek.auctionbaby.gavels.vault     → 30,000
com.valasek.auctionbaby.boost.spotlight  → 30-min Boost
```
**Non-consumables (8 status archetypes):** `...status.goodguy` … `...status.trillionaire`

**Where to reach them in the app:**
- **Subscriptions/paywall:** My Bids → **Upgrade**, or the filters / rank-reveal / read-receipt / rewind triggers. (The 4th-bid paywall won't fire on the all-copycat test floor — use My Bids → Upgrade.)
- **Gavel store:** tap the **Gavel counter** on the Floor, the **"Get more"** row in the bid composer, or **Profile → Settings → Store**.

---

# ROUTE A — Local StoreKit configuration (fastest, no Apple setup)

Buys are **simulated** by Xcode against the bundled `Products.storekit`. No
Apple ID, no Paid Apps agreement, no ASC products, no charges. Works in the
**Simulator** and on a **device run from Xcode**. This is the quickest way to
exercise the paywall and money-safety logic.

### A1. Confirm the scheme uses the config  ✅
- The `AuctionBaby` scheme already sets `storeKitConfiguration: Products.storekit`
  (project.yml). In Xcode: **Product → Scheme → Edit Scheme → Run → Options →
  StoreKit Configuration = Products.storekit**. If blank, select it.
- Run the app **from Xcode** (⌘R) on a sim or a connected device.

### A2. Buy every product  ✅
- Open the paywall → **Continue with Paddle/Reserve/Black Card** → the sim
  purchase sheet appears → confirm. Entitlement should activate instantly.
- Open the Gavel store → buy each pack → wallet credits by the right amount.
- Buy the Boost → 30-min boost activates. Buy a status archetype → badge equips.

### A3. Drive the edge cases from Xcode's Transaction Manager  ✅ 💰
With the app running, use **Debug → StoreKit → Manage Transactions** (or the
Transactions inspector) to:
- **Refund** a Gavel pack → 💰 the granted Gavels are **clawed back** once.
- **Refund** a status archetype → 💰 badge drops to the best still-owned tier.
- **Ask to Buy / pending** → toggle "Ask to Buy" in the config → purchase goes
  **pending**, grants nothing until approved.
- **Subscription renewal** → the config's renewal rate is accelerated; watch
  auto-renew, then **cancel** and let it lapse → entitlement ends.
- **Interrupted purchase** → force-quit the app mid-buy, relaunch → the drain
  on launch finishes it and credits once (💰 never double, never lost).

### A4. Verify prices/tiers in the config  ✅
- Each pack shows the right `displayPrice`; the store's **"+X% BONUS / BEST
  VALUE"** badges read off those prices. Adjust prices in `Products.storekit`
  if you want to preview a different ladder (this file is test-only).

> Route A limits: it's **not** the real StoreKit server, so it can't validate
> ASC product setup, real receipts, or the production grant path. That's Route B.

---

# ROUTE B — Real App Store Sandbox (required before submission)

Real StoreKit, real receipts, a real (test) Apple ID — but **no money charged**.
This is the pass that proves the ASC setup and the live purchase pipeline.

### B1. Account & agreements  🔴
- 🔴 **Paid Apps agreement** Active (ASC → **Business → Agreements, Tax, and
  Banking**). Without it, `Product.products()` returns **empty** and every buy
  button is dead — this is the #1 "products won't load" cause.
- Bundle id `com.valasek.auctionbaby` registered with the IAP capability.

### B2. Create + ready the products  🔴
- All **16 IAP** created with the **exact IDs** above (see `LAUNCH_RUNBOOK.md`
  Step 7 for the full table + decided prices).
- Each needs display name + description + a **review screenshot**, then state
  **"Ready to Submit"** (products in `MISSING_METADATA` won't load in sandbox).
- Subscriptions grouped as **"Auction Baby Pass"**, ranked Paddle < Reserve <
  Black Card, monthly.
- ⚠️ `status.trillionaire` at **$9,999.99** needs Apple **custom pricing**.

### B3. Create a Sandbox tester  🔴
- ASC → **Users and Access → Sandbox → Testers → +**. Use an email you control
  that is **NOT** an existing Apple ID. Note the password. (Region sets the
  storefront/currency you'll see.)
- Never sign your **real** Apple ID into sandbox.

### B4. Put the sandbox account on the device  ✅
- Install a **development-signed** build (run from Xcode or Ad Hoc) — TestFlight
  also works and uses sandbox automatically.
- On the device: **Settings → Developer → Sandbox Apple Account → Sign In** with
  the B3 tester. (If "Developer" isn't shown, connect the device to Xcode once.)
- Do **not** sign it into Settings → Media & Purchases; sandbox is separate.

### B5. Buy every product in sandbox  ✅ 💰
Run through the **whole matrix** — the sheet will say **[Environment: Sandbox]**:
- ☐ **Buy** each of the 3 subs → entitlement active; usage flips to Unlimited;
      Reserve unlocks reserve-price/filters/rewind; Black Card unlocks read receipts.
- ☐ **Buy** each Gavel pack → wallet credits 1,000/5,000/14,000/30,000.
- ☐ **Buy** the Boost → 30-min boost; **Buy** a couple archetypes → badge equips.
- ☐ **Cancel** the sheet → no entitlement, no phantom credit.
- ☐ **Ask to Buy** (if simulating a family child) → pending, no grant.
- ☐ **Restore Purchases** (paywall toolbar) on a fresh install → subs + archetypes come back.
- ☐ **Upgrade/downgrade** across the 3 sub tiers → subscription-group ranking resolves; no double charge.
- ☐ 💰 **Refund** a Gavel pack (ASC sandbox refund, or wait for auto) → Gavels clawed back once.
- ☐ 💰 **Kill mid-purchase** → relaunch → credited exactly once (drain path).
- ☐ **Auto-renew**: sandbox monthly renews on an **accelerated** clock (~every
      few minutes); confirm renewal, then cancel → lapses.

### B6. Sandbox subscription renewal speeds (so you're not confused)
| Real period | Sandbox renews every |
|---|---|
| 1 week | ~3 min |
| 1 month | ~5 min |
| (auto-renews ~6 times, then stops) | |

---

## What "pass" looks like (money-safety invariants) 💰
- Every consumable credits **exactly once**, even across kill/relaunch (keyed by `transaction.id`).
- Cancel/pending **never** grants.
- Refund **claws back** exactly what was granted (Gavels or badge); a later
  reversal restores it.
- Restore returns subs + archetypes on a clean install.
- Terms + Privacy links on the paywall **open** (needs `AB_TERMS_URL`/`AB_PRIVACY_URL`
  or the hosted fallback — see runbook Steps 2–3).

## The App Review path (not sandbox — don't confuse them)
**Demo Mode** (onboard with name `demo`) shows a **"Demo: activate <tier> free"**
button and grants status free — for the reviewer, no purchase. Keep this working,
but it is **separate** from sandbox buying.

---

## Troubleshooting — "the buttons do nothing / no products"
| Symptom | Cause / fix |
|---|---|
| All buy buttons greyed, "products load from the App Store…" | Products not loaded. **Route A:** scheme's StoreKit config not selected → set it, re-run from Xcode. **Route B:** Paid Apps agreement not Active, or products not "Ready to Submit", or ID mismatch. |
| Products load in sim but not on device | Device build wasn't **run from Xcode** (so no local config) and sandbox isn't set up → do Route B, or run from Xcode. |
| "Cannot connect to iTunes Store" (sandbox) | Wrong/again-prompting sandbox account; sign in via **Settings → Developer → Sandbox Apple Account**, not Media & Purchases. |
| Sub shows active forever | A lingering sandbox sub or a `demoTier` — reset between passes (delete app / new sandbox tester). |
| `trillionaire` won't load | Needs **custom pricing** approved in ASC. |

## Recommended order
1. **Route A today** — verify the paywall + Gavel store + every money-safety edge with zero Apple setup.
2. Finish **B1–B3** (agreement, products Ready, sandbox tester).
3. **Route B** full matrix on the device → then Archive → TestFlight → submit.
