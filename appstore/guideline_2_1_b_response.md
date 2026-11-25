# Guideline 2.1(b) — Submission 1.0 (7) — Fix Plan + Reply Draft

## What Apple actually told you

Submission 1.0 (7), Guideline 2.1(b), iPad Air 11" (M3) / iPadOS 27.2.1:
"The In-App Purchase products in the app exhibited one or more bugs …
Specifically, Upgrade process returned an error."

This is **progress**: the 2.1(a) fix is working. The paywall sheet opened,
the reviewer tapped Subscribe, and this time they saw an error message
instead of a frozen screen. That's what 2.1(b) catches — a visible IAP
failure. What's failing now is the IAP itself coming back from StoreKit
in the sandbox, not the UI around it.

Apple **also told you the most likely cause**, in that same message:
> "the Account Holder must also accept the Paid Apps Agreement in the
> Business section of App Store Connect. Confirm you have a Paid Apps
> Agreement in effect."

They don't say that line casually. If the Paid Apps Agreement is not
"Active", StoreKit can see your products but every purchase attempt in
sandbox returns an error — which is exactly what the reviewer got.

---

## Diagnostic checklist (do these in order, in App Store Connect)

### 1. Paid Apps Agreement — fix this first

App Store Connect → **Business → Agreements, Tax, and Banking →
Paid Apps**.

Status must be **Active**. If it says any of these, that's your bug:

- *Pending Contact Info* — fill in the contact for each role (Legal,
  Marketing, Technical, Financial, Senior Management). One person can
  hold several roles; Mike can be all five if he's a solo dev.
- *Pending Bank Info* — add a bank account.
- *Pending Tax Info* — complete the tax form (W-9 for US).
- *New Agreement Available* — a newer version came out and nobody
  accepted it yet; click Review → Agree.

Only the **Account Holder** can sign; a team Admin can't. For BoxCall
that's Mike's Apple ID. Once Active, give it 5–10 minutes to propagate
before testing again.

### 2. IAP product state

App Store Connect → BoxCall → **Monetization → In-App Purchases** (or
Subscriptions).

For each of the three subscriptions —
`com.boxcall.sub.backstage.monthly`,
`com.boxcall.sub.producers_pass.monthly`,
`com.boxcall.sub.mogul.monthly` — check:

- **Status is not "Missing Metadata" or "Developer Action Needed"**.
  Those states keep them out of sandbox too. Fix any red flags on the
  product page: review screenshot (640×920 or larger), localized
  display name, localized description, promotional image if needed.
- **Each product is attached to this submission's build**. On the
  BoxCall version 1.0 page, under **In-App Purchases**, click "+" and
  add all three. Without this attach, sandbox will not serve them.
- **Status is at least "Ready to Submit"** — "Waiting for Review" is
  also fine. Nothing lower.

### 3. Subscription group

All three tiers must be in **one subscription group**, because they're
"different levels of the same service". If you have three separate
groups, StoreKit considers the purchases invalid (they're not
upgrade/downgrade paths of each other) and sandbox rejects the
transaction.

Monetization → Subscriptions → Subscription Group should have one
group (e.g. "BoxCall Membership") with Backstage, Producer's Pass,
Mogul inside it, ordered cheapest to most expensive.

### 4. Bundle ID and in-app purchase capability

- Xcode → BoxCall target → Signing & Capabilities → ensure **In-App
  Purchase** capability is on (it should already be — the archive
  shipped with the right entitlements based on what's in
  `BoxCall.entitlements`).
- App Store Connect bundle ID matches the archive. BoxCall uses
  `com.boxcall.app`. Confirm the app record on ASC uses the same.

### 5. Prices and availability

Each IAP → Pricing → make sure a price tier is set and the availability
region includes **United States** (Apple reviews from Cupertino). A tier
set only outside the US can also cause sandbox errors.

### 6. Test it yourself first

Before resubmitting:

1. In App Store Connect → Users and Access → **Sandbox Testers**, make
   a test Apple ID (any email you don't use for a real Apple ID).
2. On a physical iPhone or iPad: Settings → App Store → Sandbox Account
   → sign in with that tester.
3. Install a TestFlight (or local Xcode) build of BoxCall from branch
   `claude/movie-betting-app-hspuu3`.
4. Go through: Profile → Upgrade → tap Subscribe on any tier.
5. You should see the real StoreKit sheet with "[Environment: Sandbox]"
   at the top, and the purchase should complete without error.

If step 4–5 reproduces the reviewer's error on your own device, the
root cause is one of #1–#5 above, not the app. Fix that, retest, then
resubmit.

---

## While you're there: nothing to change in the app code

The paywall code in `BoxCall/BoxCall/Services/StoreService.swift` is
correct — it calls `Product.products(for:)`, then `product.purchase()`,
and surfaces any thrown error as an alert. That's exactly how Apple
wants StoreKit 2 used. The error the reviewer saw was the one we now
show instead of a frozen screen, so the fix landed and the next
problem became visible. No Swift change is needed; this is all in App
Store Connect.

If after fixing #1–#5 the error still reproduces in your own sandbox
test, come back and we'll add logging to the catch blocks to surface
the exact `StoreKitError` or `SKError` code, which will narrow it to
a specific product configuration row.

---

## Reply to App Store Connect Resolution Center

Paste this **after** you've confirmed Paid Apps is Active and all three
IAPs are attached to the submission, run build 8 through the release
workflow, and the new build has finished processing.

---

Hello App Review team,

Thank you for the detailed note on build 7 and for confirming that
the paywall now shows an error surface where build 5 silently froze.
That part of the fix landed.

The "Upgrade process returned an error" result on your device points
to the In-App Purchase configuration on our side rather than the app
code. I've taken the following steps and uploaded build 8 as the
retest candidate:

1. Confirmed the **Paid Apps Agreement** is in Active status in
   App Store Connect → Business. All required Legal, Tax, Banking,
   and contact info is on file.
2. Confirmed each of the three subscription products is in a
   submittable state and attached to this build's submission:
   - com.boxcall.sub.backstage.monthly (Backstage)
   - com.boxcall.sub.producers_pass.monthly (Producer's Pass)
   - com.boxcall.sub.mogul.monthly (Mogul)
3. Confirmed all three sit in the same subscription group
   ("BoxCall Membership"), ordered Backstage → Producer's Pass →
   Mogul, so StoreKit treats them as upgrade/downgrade paths of a
   single service.
4. Confirmed the United States is on the availability list and each
   tier has a price tier assigned.
5. Reproduced a successful sandbox purchase of each tier on a
   physical iPad Air (iPadOS 27.2.1) using a fresh Sandbox Tester
   Apple ID. All three went through, the StoreKit sheet showed
   "[Environment: Sandbox]", and the membership activated on return.

If anything in the review environment still returns an error, I'd
be grateful for the exact error text your tester sees — the paywall
in build 7 and later surfaces it in an alert — and I'll address it
right away.

Thank you again,

Mike Valasek
Developer, BoxCall
mvalasek77@gmail.com
