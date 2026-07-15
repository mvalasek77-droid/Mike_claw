# How to Set Up and Submit IAP Subscriptions in App Store Connect — Shipshot Pro

Your app is being rejected under **Guideline 2.1(b)** because the IAP products referenced in your code don't exist (or haven't been submitted for review) in App Store Connect. Apple won't approve a binary that calls StoreKit product IDs that ASC doesn't know about. Here's exactly how to fix it.

---

## Step 1: Open Your App in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Click **My Apps** → select **Shipshot** (bundle ID `com.screenshotstudio.app`)

---

## Step 2: Create the Subscription Group

1. In the left sidebar, click **Subscriptions** (under "Features" or directly in the sidebar depending on your ASC version — if you don't see it, click **In-App Purchases** → then the **Manage** link next to "Auto-Renewable Subscriptions")
2. Click the **+** button or **Create** next to "Subscription Groups"
3. **Subscription Group Reference Name**: `Shipshot Pro`
   - This is internal — users won't see it, but it organizes your tiers
4. Click **Create**

---

## Step 3: Create Each Subscription Product

Inside the "Shipshot Pro" subscription group, you need to create **3 products**. For each one:

1. Click the **+** button (or "Create" next to Subscriptions within the group)
2. Fill in these fields:

### Product 1 — Monthly

| Field | Value |
|-------|-------|
| **Reference Name** | Shipshot Pro Monthly |
| **Product ID** | Must match your code exactly — likely `com.screenshotstudio.app.pro.monthly` (check `Store.swift`) |
| **Subscription Duration** | 1 Month |

### Product 2 — Annual

| Field | Value |
|-------|-------|
| **Reference Name** | Shipshot Pro Annual |
| **Product ID** | Must match your code exactly — likely `com.screenshotstudio.app.pro.annual` |
| **Subscription Duration** | 1 Year |

### Product 3 — Lifetime

| Field | Value |
|-------|-------|
| **Reference Name** | Shipshot Pro Lifetime |
| **Product ID** | Must match your code exactly — likely `com.screenshotstudio.app.pro.lifetime` |

**Important for Lifetime:** Apple doesn't have a "lifetime" subscription duration. A lifetime unlock is a **Non-Consumable In-App Purchase**, not a subscription. You'll create this differently:

1. Go back to the app's main page → **In-App Purchases** (not Subscriptions)
2. Click **+** → select **Non-Consumable**
3. Use the product ID that matches your code

---

## Step 4: Set Pricing for Each Product

For each subscription you created:

1. Click into the subscription product
2. Click **Subscription Pricing** (or "Add Subscription Price")
3. Select a **base country/region** (usually United States)
4. Choose your price tier:
   - Monthly: e.g., $2.99 or $4.99
   - Annual: e.g., $19.99 or $29.99
   - Lifetime (non-consumable): e.g., $49.99 or $79.99
5. Apple auto-generates prices for all other territories based on your base price
6. Click **Next** → **Confirm**

> **You cannot submit for review without pricing set.** This is a common reason 2.1(b) triggers.

---

## Step 5: Add Localization (Display Name + Description)

For each product:

1. Click into the product
2. Under **App Store Localization** or **Subscription Localization**, click **+** or the existing language
3. Fill in:

| Field | Example for Monthly |
|-------|---------------------|
| **Display Name** | Shipshot Pro — Monthly |
| **Description** | Unlock all templates, custom branding, and unlimited exports. Renews monthly. |

Do this for every product, in at least **one language** (English).

> **You cannot submit for review without localizations.** This is another common 2.1(b) trigger.

---

## Step 6: Add the App Review Screenshot (CRITICAL)

**This is almost certainly why you keep getting rejected.** Each IAP product needs a screenshot that shows the user what they're buying.

For each product:

1. Click into the product
2. Look for **Review Information** or **App Review Information** section
3. Under **Screenshot**, upload a screenshot that shows:
   - Your paywall screen (the `PaywallView` in your app)
   - Or a screen showing the premium features the user gets
4. The screenshot must be:
   - At least 640x920 pixels
   - A real screenshot from your app (use the Simulator or a real device)
   - Shows what the purchase unlocks

### How to capture the screenshot

1. Run Shipshot in Simulator
2. Navigate to the paywall/upgrade screen
3. Press **Cmd+S** in Simulator to save a screenshot
4. Upload that PNG to each IAP product's Review Information section

You can use the **same screenshot** for all 3 products if they all unlock the same "Pro" features.

---

## Step 7: Add Review Notes (Optional but Recommended)

In each product's Review Information section, there's a **Review Notes** text field. Add something like:

> "This subscription unlocks Shipshot Pro features including all device templates, custom branding, and unlimited high-resolution exports. The paywall is accessible from the Settings tab or when the user tries to use a Pro-only feature."

This helps the reviewer find and test your IAP flow.

---

## Step 8: Set Subscription Group Localization

1. Go back to the **Subscription Group** level (click "Shipshot Pro" group name)
2. Under **App Store Localization**, click **+**
3. Set:
   - **Subscription Group Display Name**: `Shipshot Pro`
   - **App Name (optional)**: `Shipshot`
4. Save

---

## Step 9: Verify Product ID Match

This is the most common source of 2.1(b) rejections. The product IDs in ASC must be **character-for-character identical** to what's in your Swift code.

To verify, find the product IDs in your `Store.swift` file. They should look something like:

```swift
static let monthlyID = "com.screenshotstudio.app.pro.monthly"
static let annualID = "com.screenshotstudio.app.pro.annual"
static let lifetimeID = "com.screenshotstudio.app.pro.lifetime"
```

Whatever those strings are, the **Product ID** field in ASC must match exactly. If there's a mismatch, StoreKit returns zero products, the reviewer sees a broken paywall, and you get 2.1(b).

---

## Step 10: Check IAP Status in ASC

Before submitting, go to **In-App Purchases** and **Subscriptions** in ASC and verify each product shows status:

- **Ready to Submit** — this is what you need
- **Missing Metadata** — go back and add the missing localization, price, or screenshot
- **Developer Action Needed** — click in to see what's missing
- **Waiting for Review** or **In Review** — good, already submitted

All products must be **Ready to Submit** before you submit your app for review.

---

## Step 11: Submit the App WITH the IAPs

This is the part most people miss:

1. Go to your app's **App Store** tab → the version you're submitting (1.0)
2. Scroll down to the **In-App Purchases and Subscriptions** section (or it may be called **In-App Purchases** near the bottom of the version page)
3. Click **+** next to this section
4. **Select all 3 of your IAP products** from the list
5. Click **Done** / **Add**

> **If you don't explicitly add the IAPs to the version, they won't be submitted for review even if they exist in ASC.** This is the most common cause of repeated 2.1(b) rejections.

6. Now click **Add for Review** / **Submit for Review** at the top of the version page

---

## Step 12: Agreements

Before IAPs can work, you need to have signed the **Paid Applications Agreement** in ASC:

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Agreements, Tax, and Banking** (or **Business** in newer ASC)
2. Make sure the **Paid Apps** agreement is **Active** (green)
3. If it says "New Agreement Available" — accept it
4. You need valid **banking** and **tax** information on file

If this agreement isn't active, IAPs won't load at all, and Apple will reject under 2.1(b).

---

## Quick Checklist Before Resubmitting

- [ ] Subscription group "Shipshot Pro" created in ASC
- [ ] Monthly subscription created with correct Product ID matching code
- [ ] Annual subscription created with correct Product ID matching code
- [ ] Lifetime purchase created (as Non-Consumable) with correct Product ID matching code
- [ ] Pricing set for all 3 products
- [ ] Localization (display name + description) added for all 3 products in at least English
- [ ] App Review screenshot uploaded for each product (paywall screenshot works for all 3)
- [ ] All 3 products show status "Ready to Submit" (not "Missing Metadata")
- [ ] All 3 products are **added to the app version** in the version's IAP section
- [ ] Paid Applications Agreement is active in Agreements/Business
- [ ] Privacy Policy URL is set in App Information (required for subscriptions)
- [ ] Product IDs in ASC match `Store.swift` exactly — copy-paste, don't retype

---

## Common Gotchas That Cause 2.1(b)

1. **Products exist but aren't attached to the version** — #1 cause. You must explicitly select them in the version's IAP section.
2. **Missing App Review screenshot** — Apple requires this for every IAP product.
3. **Missing localization** — At minimum, add English display name and description.
4. **Product ID mismatch** — Even a trailing space or wrong capitalization breaks it.
5. **Paid Apps agreement expired or not signed** — Check Business/Agreements.
6. **Products still in "Missing Metadata" status** — They won't submit until all required fields are filled.

Once all items are green, submit the new build and the IAPs will go through review together. The reviewer will test your paywall flow in Sandbox mode.
