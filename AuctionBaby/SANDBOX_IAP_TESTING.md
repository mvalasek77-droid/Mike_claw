# Sandbox IAP Testing — Auction Baby

Two routes so you're never blocked.

---

## Route A — Local StoreKit Testing (no ASC needed, works now)

The `Products.storekit` configuration file is already in the scheme. It provides all 16 IAP products locally — no App Store Connect required.

### On Simulator (fastest)

```bash
# Build + run tests (StoreKit config auto-attached via scheme test action)
cd ~/code/mike_claw/AuctionBaby
xcodebuild test \
  -project AuctionBaby.xcodeproj \
  -scheme AuctionBaby \
  -destination 'platform=iOS Simulator,id=404E9341-3F05-4536-BD30-B696DFD57DFE' \
  -only-testing:AuctionBabyTests/StoreCatalogTests
```

Or to interact manually:
1. Open Xcode: `open AuctionBaby.xcodeproj`
2. Select **AuctionBaby** scheme → **iPhone 17 Pro Max** simulator
3. **Cmd+R** — StoreKit config is injected automatically
4. All products show with prices and are purchasable (simulated, no charge)

### On Physical Device (iPhone 17 Pro Max)

**Must run from Xcode** — `xcodebuild` + `devicectl install` does NOT inject the StoreKit config.

1. Open Xcode: `open AuctionBaby.xcodeproj`
2. Select **AuctionBaby** scheme → **iPhone 17 Pro Max** (physical device)
3. **Cmd+R** — StoreKit config is injected on launch
4. Navigate to **You → Store** → all products show prices and are tappable

### Products in the StoreKit config

| Type | Product ID | Name | Price |
|---|---|---|---|
| Consumable | `com.valasek.auctionbaby.gavels.handful` | Handful of Gavels | $4.99 |
| Consumable | `com.valasek.auctionbaby.gavels.stack` | Stack of Gavels | $19.99 |
| Consumable | `com.valasek.auctionbaby.gavels.chest` | Chest of Gavels | $49.99 |
| Consumable | `com.valasek.auctionbaby.gavels.vault` | Vault of Gavels | $99.99 |
| Consumable | `com.valasek.auctionbaby.boost.spotlight` | Spotlight Boost | $4.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.goodguy` | Good Guy | $4.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.inandout` | In & Out Guy | $9.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.whynot` | Why Not Guy | $19.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.goodjob` | Got a Good Job | $99.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.inheritance` | Inheritance Money Guy | $999.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.influencer` | Influencer | $2,499.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.ferrari` | I Drive a Ferrari | $4,999.99 |
| Non-Consumable | `com.valasek.auctionbaby.status.trillionaire` | Trillionaire | $9,999.99 |
| Subscription | `com.valasek.auctionbaby.sub.paddle` | Paddle | $19.99/mo |
| Subscription | `com.valasek.auctionbaby.sub.reserve` | Reserve | $39.99/mo |
| Subscription | `com.valasek.auctionbaby.sub.blackcard` | Black Card | $99.99/mo |

### What to test

- [ ] **Gavel packs**: Buy each pack → wallet balance updates → value badge shows correct % vs base
- [ ] **Spotlight Boost**: Buy → 30-min timer starts → boost badge on profile
- [ ] **Pass subscriptions**: Subscribe to Paddle → `hasPass = true` → bid limit lifted
- [ ] **Status archetypes**: Buy Good Guy → badge appears on profile
- [ ] **Restore**: Tap Restore → re-grants all previous purchases
- [ ] **Cancel subscription**: Cancel in sandbox → entitlement expires at period end
- [ ] **Interrupted purchase**: Background the app mid-purchase → no charge, no entitlement

---

## Route B — ASC Sandbox Testing (real Apple servers)

Once the products in App Store Connect have full metadata (name, description, screenshot, price), you can test with a real sandbox account.

### Prerequisites

1. **Paid Apps Agreement** signed in ASC → Business
2. All 16 products created in ASC with:
   - Display name + description
   - Price (matching the table above)
   - Review screenshot
   - Status: **Ready to Submit**
3. Products attached to the app version

### Create a Sandbox Account

1. ASC → **Users and Access** → **Sandbox** → **Test Accounts** → **+**
2. Use a unique email (not a real Apple ID)
3. Set country to match your App Store region

### Test on Device

1. **Settings → App Store → Sandbox Account** (appears when a debug build is installed)
2. Sign in with the sandbox account
3. Run the app from Xcode (Cmd+R) — products now fetch from ASC sandbox
4. Purchase each product — sandbox accounts don't charge real money
5. Check `StoreKitService` logs in Console.app

### Sandbox Limitations

- Subscriptions auto-renew fast (5 min for monthly in sandbox)
- Purchases are simulated but go through real StoreKit APIs
- Sandbox account is device-wide (not per-app)
- Can't test family sharing without a family group

---

## Troubleshooting

| Issue | Fix |
|---|---|
| "Unavailable" on Pass buttons | Run from Xcode (Cmd+R), not `xcodebuild` + `devicectl` |
| Products don't load | Check scheme has `Products.storekit` in StoreKit config |
| "Cannot connect to App Store" | Sign out of sandbox account, sign back in |
| Purchase fails silently | Check Console.app for StoreKit errors |
| Subscriptions not found | Verify subscription group "Auction Baby Pass" exists in ASC |