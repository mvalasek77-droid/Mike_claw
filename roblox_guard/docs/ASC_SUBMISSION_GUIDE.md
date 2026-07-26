# App Store Connect Submission Guide — RobloxGuard

Every field you need to fill in to submit RobloxGuard for review, with exact
values and copy-ready text. Open this next to ASC.

> **Status:** Values below are cross-checked against the actual codebase.
> The privacy policy URL and support email match what's hardcoded in
> `PaywallView.swift` and `BugReportView.swift`.

---

## App Information

### General → App Information

| Field | Value | Notes |
|---|---|---|
| **Name** | `RobloxGuard` | 30-char limit. Appears on App Store and home screen. |
| **Subtitle** | `Roblox safety alerts for parents` | 30-char limit. Shows below name on listing. |
| **Bundle ID** | `com.mikeclaw.robloxguard` | Must match `project.yml` — already set. |
| **Primary Language** | `English (U.S.)` | |
| **Primary Category** | `Utilities` | |
| **Secondary Category** | `Lifestyle` | Do **NOT** select "Kids" or "Education" — this is a parent-facing utility. Kids Category triggers COPPA-specific requirements that don't apply and could cause rejection. |
| **Content Rights** | Does not contain, show, or access third-party content | RobloxGuard reads public Roblox API data but doesn't embed or display third-party copyrighted content. Alerts are your own generated analysis. |

---

## Pricing & Availability

| Field | Value |
|---|---|
| **Price** | Free |
| **Availability** | Available in all territories |

The app is free to download. Revenue comes from auto-renewable subscriptions configured separately under In-App Purchases.

---

## App Privacy

### Privacy Policy URL (Required)

```
https://mvalasek77-droid.github.io/Mike_claw/robloxguard-privacy.html
```

This URL must be live before you submit. Host the content from `docs/PRIVACY_POLICY.md` at this URL. It must match the constant in `PaywallView.swift`:

```swift
static let privacyPolicyURL = URL(string: "https://mvalasek77-droid.github.io/Mike_claw/robloxguard-privacy.html")!
```

### Data Collection Question

**"Do you or your third-party partners collect data from this app?"**

→ **Yes**

> Answering "No" when you do collect data is grounds for rejection and could result in app removal.

### Data Types to Declare

| Data Type | Category | Purpose | Linked to User? | Used for Tracking? |
|---|---|---|---|---|
| Name | Contact Info | App Functionality | Yes | No |
| User ID | Identifiers | App Functionality | Yes | No |
| Email Address | Contact Info | App Functionality | Yes | No |
| Photos or Videos | User Content | App Functionality | Yes | No |
| Device ID | Identifiers | App Functionality | No | No |
| Purchase History | Purchases | App Functionality | Yes | No |

### For Each Data Type — Sub-Questions

| Purpose | Check? |
|---|---|
| Used for App Functionality | ✅ Check for ALL |
| Used for Analytics | ❌ Leave unchecked for all |
| Used for Developer's Advertising | ❌ Leave unchecked for all |
| Used for Third-Party Advertising | ❌ Leave unchecked for all |
| Used for Tracking | ❌ Leave unchecked for all |

**Why each data type:**
- **Name** — Parent's name, recorded as the consent attestation when linking a child
- **User ID** — Child's public Roblox username and Roblox account ID
- **Email Address** — Optional, only if the parent provides it in a bug report
- **Photos or Videos** — Evidence screenshots the parent uploads to the evidence vault
- **Device ID** — APNs push notification token (not linked to identity)
- **Purchase History** — Subscription tier from StoreKit (Apple handles all payment details)

---

## Age Rating

### General → Age Rating

| Question | Answer | Rationale |
|---|---|---|
| Cartoon or Fantasy Violence | None | |
| Realistic Violence | None | |
| Prolonged Graphic or Sadistic Realistic Violence | None | |
| Profanity or Crude Humor | None | |
| Mature/Suggestive Themes | **Infrequent/Mild** | The app discusses online grooming and child safety risks in educational content. It never depicts mature content, but the subject matter is sensitive. |
| Horror/Fear Themes | None | |
| Medical/Treatment Information | None | |
| Simulated Gambling | None | |
| Sexual Content or Nudity | None | |
| Alcohol, Tobacco, or Drug Use or References | None | |
| Unrestricted Web Access | **No** | The app has no web browser. External links (Roblox profile, NCMEC) open in Safari. |
| Gambling and Contests | No | |

**Expected result:** 4+ age rating. The "Infrequent/Mild" on Mature Themes may bump it to 9+ or 12+, which is fine for a parent-facing utility.

---

## Version Information

### App Store → iOS App → Version

#### Promotional Text (optional, editable anytime)

```
Now with push notifications — get alerted the moment something changes.
```

170 characters max. Appears above the description.

#### Description (required)

```
RobloxGuard is a parent-only companion app that watches your child's public Roblox footprint and alerts you to the observable precursors of online grooming — before it escalates.

HOW IT WORKS
Install RobloxGuard on your phone (not your child's). Enter their public Roblox username — no password, no device access needed. The app monitors their public friend list, friends' profiles, and online activity around the clock and alerts you when something looks off.

WHAT IT WATCHES FOR
• Friends whose bios advertise Discord, Snapchat, Telegram, or other off-platform handles — the strongest observable grooming precursor
• Bios containing known solicitation phrases
• Unusually old accounts befriending your child
• Accounts with suspiciously large friend networks (mass-friending)
• Sudden bursts of new friends
• Activity during late-night hours you set
• Experiences flagged by safety researchers

WHAT YOU GET
• Real-time push notifications for watch-level and elevated alerts
• Plain-language explanations — every Roblox term is defined inline
• An evidence vault that preserves exactly what was observed
• Incident reports formatted for Roblox's Report Abuse tools and NCMEC's CyberTipline
• Educational content: "Know the Dangers," a grooming-precursor glossary, and a response playbook

BUILT FOR HONESTY
This app will sometimes be wrong. It will flag something innocent and miss something real. Every alert says so, and onboarding requires you to acknowledge it. RobloxGuard is one tool alongside talking to your child and using Roblox's own parental controls — not a substitute for either.

WHAT IT CANNOT DO
RobloxGuard cannot read private Roblox chats. No outside app can — only Roblox's own moderators see them. Any product claiming otherwise is violating Roblox's Terms of Use. That's exactly why reporting to Roblox matters: they can see what this app can't.

NOTHING ON YOUR CHILD'S DEVICE
Nothing is installed on or connected to your child's phone, tablet, or computer. There's nothing for them to find or delete. The app runs entirely on your device, using only publicly visible Roblox data.

PRIVACY
We store only what's necessary: your child's Roblox username, the safety alerts we generate, and evidence you choose to save. No third-party analytics. No ads. No data sold. Unlinking a child permanently deletes everything associated with them.

SUBSCRIPTION
• Single Child: $3.99/month or $34/year
• Family (up to 5 children): $8.99/month or $69/year
```

~2,100 characters — well within the 4,000 character limit.

> **Note:** The guide template said "up to 4 children" for Family tier, but the code in `PurchaseManager.swift` sets `maxChildren: 5` for `.family`. The description above has been corrected to say "up to 5 children."

#### Keywords (required)

```
roblox,parental,safety,grooming,monitor,child,protection,alerts,predator,online
```

100 characters max, comma-separated, no spaces after commas. Don't repeat words from the app name.

#### Support URL (required)

```
https://mvalasek77-droid.github.io/Mike_claw/robloxguard-support.html
```

Must be a live page. Can be a simple page with the support email (`mvalasek@gmail.com`) and FAQ.

> **Note:** The guide template said `https://robloxguard.app/support`, but you don't own that domain. Use the GitHub Pages URL where you're already hosting the privacy policy. Create a `robloxguard-support.html` page alongside the privacy page.

#### Marketing URL (optional)

```
https://mvalasek77-droid.github.io/Mike_claw/
```

#### Version Number

```
1.0
```

#### What's New in This Version

```
Initial release.
```

#### Copyright

```
2026 Mike Claw
```

No © symbol needed — Apple adds it automatically.

---

## In-App Purchases (Subscriptions)

### Monetization → Subscriptions

Create one subscription group with four products. These **must** match the product IDs in `PurchaseManager.swift` exactly:

```swift
static let singleMonthly = "com.mikeclaw.robloxguard.single.monthly"
static let singleAnnual = "com.mikeclaw.robloxguard.single.annual"
static let familyMonthly = "com.mikeclaw.robloxguard.family.monthly"
static let familyAnnual = "com.mikeclaw.robloxguard.family.annual"
```

### Subscription Group Name

```
RobloxGuard Plans
```

### Products (create in this order — Apple shows higher-tier plans first)

| # | Product Name | Product ID | Price | Duration | Reference Name |
|---|---|---|---|---|---|
| 1 | Family (Monthly) | `com.mikeclaw.robloxguard.family.monthly` | $8.99/month | 1 month | Family Monthly |
| 2 | Family (Annual) | `com.mikeclaw.robloxguard.family.annual` | $69.00/year | 1 year | Family Annual |
| 3 | Single Child (Monthly) | `com.mikeclaw.robloxguard.single.monthly` | $3.99/month | 1 month | Single Monthly |
| 4 | Single Child (Annual) | `com.mikeclaw.robloxguard.single.annual` | $34.00/year | 1 year | Single Annual |

### For Each Product — Fill In:

| Field | Family Monthly | Family Annual | Single Monthly | Single Annual |
|---|---|---|---|---|
| **Reference Name** | Family Monthly | Family Annual | Single Monthly | Single Annual |
| **Product ID** | `com.mikeclaw.robloxguard.family.monthly` | `com.mikeclaw.robloxguard.family.annual` | `com.mikeclaw.robloxguard.single.monthly` | `com.mikeclaw.robloxguard.single.annual` |
| **Subscription Duration** | 1 Month | 1 Year | 1 Month | 1 Year |
| **Price** | $8.99 | $69.00 | $3.99 | $34.00 |
| **Subscription Group** | RobloxGuard Plans | RobloxGuard Plans | RobloxGuard Plans | RobloxGuard Plans |

### Localized Description for Each Product

**Single Child (Monthly & Annual):**

```
Monitor one Roblox account with full safety alerts, evidence vault, and incident reports.
```

**Family (Monthly & Annual):**

```
Monitor up to 5 Roblox accounts with full safety alerts, evidence vault, and incident reports.
```

### Subscription Management Link

Apple requires a link to manage/cancel subscriptions. This is already handled by the `.manageSubscriptionsSheet` modifier on `SettingsView.swift` — no extra configuration needed. The reviewer may check that it works.

> **Note:** The guide template said "up to 4 children" for Family tier, but the code sets `maxChildren: 5`. The product descriptions above have been corrected to say "up to 5."

---

## Review Information

### App Store → Version → App Review Information

#### Contact Information (required)

| Field | Value |
|---|---|
| First Name | `Mike` |
| Last Name | `Valasek` |
| Phone | `[your phone number]` |
| Email | `mvalasek@gmail.com` |

#### Sign-in Required?

→ **No**

The app doesn't have user accounts or sign-in. The API token is a server-side configuration, not a user login.

#### Demo Account

Leave blank. The app doesn't have user accounts. The reviewer uses `builderman` as the test subject within the app itself.

#### Notes for Review (critical — copy this verbatim)

```
RobloxGuard is a parent-only utility that monitors a child's PUBLIC Roblox account footprint (friend list, friends' bios, online status) using Roblox's public, unauthenticated web APIs. It does NOT access private chats, require the child's password, or install anything on the child's device.

TO TEST THE APP:
1. Launch the app and complete the consent onboarding (4 toggles + Continue).
2. Tap "+" to link a child. Enter the username "builderman" (Roblox's official co-founder account — safe for testing, not a real child).
3. Enter any name for "Your name" and toggle the parental attestation.
4. Pull down to refresh — the backend polls the public Roblox API and generates safety alerts based on the account's friend list.
5. Tap any alert to see the detail view with severity, facts, guidance, and glossary definitions.
6. Go to Settings → Report a Bug to test the support flow.
7. Go to Settings → Notifications → Enable Notifications to test the push permission flow.

The subscription paywall appears when linking a second child or from Settings → Subscribe. All subscription products are auto-renewable.

DATA COLLECTION: The app collects the parent's name (consent record), child's public Roblox username, generated safety alerts, optional evidence screenshots, optional bug report email, and an APNs device token for push notifications. No third-party analytics or advertising SDKs.

The "builderman" account is Roblox's own official account and is used purely for testing — we never monitor real children's accounts during review.
```

> **Important:** This is the most important field. Reviewers read this before opening the app. Be explicit about what the app does and how to test it.

#### Attachment (optional but recommended)

Upload a short screen recording (under 30 seconds) showing the link → refresh → alert flow. This helps if the reviewer's network can't reach your backend.

---

## Export Compliance

### General → App Information

| Question | Answer |
|---|---|
| "Does your app use encryption?" | **Yes** |
| "Does your app qualify for any exemptions?" | **Yes — it uses standard HTTPS/TLS only** |

The app uses HTTPS (URLSession/TLS), which counts as encryption under US export rules. Select the exemption for apps that use only standard OS-provided networking (URLSession). No custom encryption, no proprietary protocols.

This is already declared in `project.yml`:

```yaml
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
```

This auto-answers the question on future builds — ASC won't ask again after the first time.

---

## Screenshots

### App Store → Version → Screenshots

**Required:** At least one device size. Recommended: 6.7" (iPhone 15 Pro Max / 16 Pro Max).

### Recommended Screenshots (in order)

| # | Screen | What to Show |
|---|---|---|
| 1 | Dashboard | One linked child (builderman) with 2-3 active alerts showing severity badges |
| 2 | Alert detail | An elevated alert with facts, guidance, and glossary terms |
| 3 | Know the Dangers | Education screen with a disclosure group expanded |
| 4 | Evidence vault | A saved screenshot with SHA-256 hash visible |
| 5 | Settings | Subscription status, notifications enabled, protection updates |
| 6 | Consent onboarding | The four acknowledgement toggles |

### How to Capture

1. Use the Simulator (iPhone 17 Pro Max is currently booted)
2. Enable **demo mode** in Settings → App Review → Demo Mode toggle
3. This populates the app with sample alerts and evidence — perfect for screenshots
4. Press **⌘S** in Simulator to save screenshots to Desktop
5. Or use: `xcrun simctl io <UDID> screenshot ~/Desktop/rg_shot_N.png`

> **Important:** Do not include real children's usernames in screenshots. Use `builderman` or the demo mode data. Apple reviewers check for this.

---

## Before You Submit — Final Checklist

| # | Item | Status |
|---|---|---|
| 1 | Privacy policy is live at `https://mvalasek77-droid.github.io/Mike_claw/robloxguard-privacy.html` | ☐ |
| 2 | Support page is live at `https://mvalasek77-droid.github.io/Mike_claw/robloxguard-support.html` | ☐ |
| 3 | All 4 subscription products created in ASC with correct product IDs | ☐ |
| 4 | Subscription products are in "Ready to Submit" or "Approved" status | ☐ |
| 5 | At least one set of screenshots uploaded (6.7" iPhone) | ☐ |
| 6 | App icon appears correctly in ASC (uploaded with the binary) | ☐ |
| 7 | "Notes for Review" filled in with testing instructions (copy from above) | ☐ |
| 8 | Backend is deployed and reachable from the public internet | ☐ |
| 9 | `APIClient.swift` base URL points to the deployed backend (not `localhost`) | ☐ |
| 10 | `RG_APNS_SANDBOX=0` (or unset) on the production backend | ☐ |
| 11 | `RG_API_TOKEN` set on the production backend | ☐ |
| 12 | Export compliance answered (or `ITSAppUsesNonExemptEncryption: NO` in plist — already set) | ✅ |
| 13 | Build uploaded via Xcode (Product → Archive → Distribute → App Store Connect) | ☐ |

### After Submitting

Review typically takes **24-48 hours**. You'll get an email.

**Most common rejection reasons for this type of app:**
1. Reviewer can't reach your backend → make sure it's deployed to a public URL
2. Privacy labels don't match actual collection → verified above against `db.py`
3. Subscription terms or management link missing → `.manageSubscriptionsSheet` is wired up in SettingsView

You've addressed all three.

---

## Key Differences from the Original Guide Template

The original guide had several placeholder values that don't match the actual codebase. Here's what was corrected:

| Field | Guide Template | Actual Codebase Value |
|---|---|---|
| Privacy Policy URL | `https://robloxguard.app/privacy` | `https://mvalasek77-droid.github.io/Mike_claw/robloxguard-privacy.html` |
| Support URL | `https://robloxguard.app/support` | `https://mvalasek77-droid.github.io/Mike_claw/robloxguard-support.html` (create this page) |
| Marketing URL | `https://robloxguard.app` | `https://mvalasek77-droid.github.io/Mike_claw/` |
| Family tier max children | "up to 4 children" | **up to 5 children** (`maxChildren: 5` in `PurchaseManager.swift`) |
| Export compliance | "already handled in build settings" | Confirmed: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in `project.yml` |
| Support email | Not specified in template | `mvalasek@gmail.com` (from `BugReportView.swift`) |
| Demo mode | Not mentioned | **New:** Enable demo mode in Settings → App Review for screenshots and reviewer testing without a backend |