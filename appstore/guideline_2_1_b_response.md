# Guideline 2.1(b) — Submission 1.0 (7) — Fix Plan + Reply Draft

## Root cause (confirmed in App Store Connect, Nov 26)

BoxCall has **no subscription products in App Store Connect**: no group, no
products. The app asks StoreKit for three product IDs, StoreKit returns
nothing, and the paywall shows an error. That error is what the reviewer saw.

The Paid Apps Agreement is Active, and the app code is correct. Nothing in the
binary needs to change, so **resubmit build 7** once the products exist.

---

## Step 1 — Create the subscription group

Monetization → Subscriptions → Create Subscription Group

- Reference Name: `BoxCall Membership`
- After creating it, add a **group localization** (English (U.S.)):
  Subscription Group Display Name `BoxCall Membership`. The group won't
  submit without one.

## Step 2 — Create the three subscriptions in that group

> **Product IDs are permanent.** Once saved, an ID can never be changed or
> reused, even if you delete the product. Paste them from this table
> rather than typing them, and check each one against it before saving.

| | Backstage | Producer's Pass | Mogul |
|---|---|---|---|
| Reference Name | `Backstage Monthly` | `Producer's Pass Monthly` | `Mogul Monthly` |
| Product ID | `com.boxcall.sub.backstage.monthly` | `com.boxcall.sub.producers_pass.monthly` | `com.boxcall.sub.mogul.monthly` |
| Duration | 1 Month | 1 Month | 1 Month |
| Price (USA base) | $3.99 | $9.99 | $14.99 |
| Display Name (en-US, ≤30) | `Backstage` | `Producer's Pass` | `Mogul` |
| Description (en-US, ≤45) | `Ticket badge, early access, 3 limit orders` | `Star badge, stats, 10 limit orders` | `Pro analytics, CSV export, unlimited orders` |
| Level in group | 3 (lowest) | 2 | 1 (highest) |

These values match `Membership.swift` and `BoxCall/Products.storekit`.

For each one also set:
- **Availability:** all countries, or at least the United States.
- **Review Information → Screenshot:** a screenshot of the BoxCall paywall
  (Profile → Upgrade) at iPhone size (for example 1290×2796). The same image
  works for all three.
- **Review Notes:** `Profile tab → Upgrade → Subscribe on this tier.`
- **Family Sharing:** off.

**Level matters.** In App Store Connect, level 1 is the highest tier. Drag
Mogul to the top and Backstage to the bottom so upgrades and downgrades work
in the right direction.

Each subscription should end at **Ready to Submit**. If any shows "Missing
Metadata", open it and fill in whatever field is flagged.

## Step 3 — Attach them to the submission

On the BoxCall 1.0 version page, in **In-App Purchases and Subscriptions**,
click + and select all three. An app's first subscriptions must be submitted
together with an app version, so without this step the reviewer still gets
nothing.

## Step 4 — Sandbox test before resubmitting

1. Users and Access → Sandbox → Test Accounts → create a tester using an email
   that isn't a real Apple ID.
2. On the iPad: Settings → App Store → Sandbox Account → sign in as the tester.
3. Open build 7 from TestFlight → Profile → Upgrade → Subscribe on each tier.
4. The purchase sheet should say "Environment: Sandbox", and the purchase
   should complete. The new products can take up to an hour to appear in the
   sandbox. If the app still says "Subscriptions aren't available", wait and
   retry before changing anything.

## Step 5 — Resubmit build 7 with the reply below

---

## Reply to App Store Connect Resolution Center

Paste this only after Steps 1–4 are done and a sandbox purchase works.

---

Hello App Review team,

Thank you for testing build 7 and for the clear description of the upgrade
error.

The cause was on our side in App Store Connect: BoxCall's three subscription
products had not been created, so StoreKit had nothing to return and the
paywall correctly showed an error. My earlier note for build 5 suggested the
products were still in review. That was wrong, and I apologize for the
confusion.

I've now done the following:

1. Created the "BoxCall Membership" subscription group with three monthly
   auto-renewable subscriptions:
   - com.boxcall.sub.backstage.monthly — Backstage, $3.99/month
   - com.boxcall.sub.producers_pass.monthly — Producer's Pass, $9.99/month
   - com.boxcall.sub.mogul.monthly — Mogul, $14.99/month
2. Completed their metadata and review screenshots, and attached all three to
   this submission.
3. Confirmed the Paid Apps Agreement is active.
4. Purchased each tier successfully in the sandbox on an iPad running
   iPadOS 27.2.1.

The app binary is unchanged, so I'm resubmitting build 7. To test: Profile tab
→ Upgrade → Subscribe on any plan.

Thank you,

Mike Valasek
Developer, BoxCall
