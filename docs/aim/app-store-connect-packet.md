# App Store Connect submission packet — AI Marketplace v1.0

Open App Store Connect in one tab, this file in another. Walk down it linearly.
For each section: paste the value, click Save, scroll to the next field.

Total time end-to-end: ~30 min (excluding screenshot creation).

---

## 0. Before you start

**Confirm these are done:**
- [ ] Paid Apps Agreement signed (App Store Connect → Business → Agreements)
- [ ] Bundle ID `com.valasek.aimarketplace` registered (developer.apple.com → Identifiers)
- [ ] App record created in App Store Connect → My Apps → AI Marketplace
- [ ] Four IAPs created and Ready to Submit (Tier 5/10/15/20)
- [ ] At least one TestFlight build uploaded via Xcode Cloud
- [ ] GitHub Pages serving from a branch where `docs/aim/` exists, so these resolve:
  - https://mvalasek77-droid.github.io/Mike_claw/aim/privacy.html
  - https://mvalasek77-droid.github.io/Mike_claw/aim/terms.html
  - https://mvalasek77-droid.github.io/Mike_claw/aim/support.html

---

## 1. App Information

App Store Connect → My Apps → AI Marketplace → **App Information** (left sidebar).

### General Information

| Field | Value |
|---|---|
| Name | `AI Marketplace` |
| Subtitle (≤30 chars) | `AI novels, music & films` |
| Bundle ID | (already set — `com.valasek.aimarketplace`) |
| SKU | `aimarketplace-001` (or whatever you used) |
| Primary Language | `English (U.S.)` |

### Category

| Field | Value |
|---|---|
| Primary Category | `Entertainment` |
| Secondary Category | `Books` *(optional but boosts discovery for novel buyers)* |

### Content Rights

> "Does your app contain, show, or access third-party content?"

**No.** *(Sample catalog created by you with AI tools you license; user-generated content is UGC, not third-party.)*

### Age Rating

Click **Edit** → answer the questionnaire (full answers in §4 below).

### Privacy Policy URL

```
https://mvalasek77-droid.github.io/Mike_claw/aim/privacy.html
```

---

## 2. Pricing and Availability

App Store Connect → **Pricing and Availability** (left sidebar).

### Price

| Field | Value |
|---|---|
| Price | **Free** *(app itself is free; revenue is via IAP)* |

### Availability

- **All countries and regions** with these exclusions (manual uncheck):
  - China mainland *(needs ICP license)*
  - Russia *(Stripe payout complications)*
  - Iran, North Korea, Syria, Crimea, Donetsk PR, Luhansk PR, Cuba *(US sanctions)*

### Distribution

- **Available on the App Store** ✓
- **TestFlight Internal Testing** ✓
- Mac/Vision distribution: leave as configured during build upload

---

## 3. App Privacy

App Store Connect → **App Privacy** (left sidebar).

> "Does this app collect data?"

**Yes**

For each data type, click **Add** → set fields per the table:

| Data Type | Collected? | Linked to user? | Used for Tracking? | Purposes |
|---|---|---|---|---|
| Email Address | ✓ | Yes | No | App Functionality |
| Name | ✓ | Yes | No | App Functionality |
| User ID | ✓ | Yes | No | App Functionality |
| Purchase History | ✓ | Yes | No | App Functionality |
| Other Financial Info | ✓ | Yes | No | App Functionality |
| Audio Data | ✓ | Yes | No | App Functionality |
| Video Data | ✓ | Yes | No | App Functionality |
| Other User Content | ✓ | Yes | No | App Functionality |

**"Used for Tracking" should be No on every row.** You don't run ads or share data with data brokers.

---

## 4. Age Rating

App Store Connect → **Age Rating** (under App Information → Edit).

Answer each row exactly as below. Result will be **12+**.

| Category | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | **Infrequent/Mild** |
| Sexual Content or Nudity | **Infrequent/Mild** |
| Graphic Sexual Content and Nudity | None |
| Alcohol, Tobacco, or Drug Use or References | **Infrequent/Mild** |
| Mature/Suggestive Themes | **Infrequent/Mild** |
| Horror/Fear Themes | **Infrequent/Mild** |
| Medical/Treatment Information | None |
| Simulated Gambling | None |
| Contests | None |
| Unrestricted Web Access | **No** |
| Gambling and Contests | No |

### If Apple asks for justification on any Infrequent/Mild row, paste:

> "User-published AI-generated novels, music, and films may include incidental mature themes (profanity, references to alcohol/tobacco/drugs, mild suggestive content, tension and fear) consistent with adult-oriented fiction. All submissions pass an automated quality and content review (the AI Editor) that rejects sexually explicit material, graphic violence, and content that glorifies illegal drug use. Users can report objectionable titles in-app; reports are reviewed within 24 hours by operator moderation."

---

## 5. App Review Information

App Store Connect → **App Review Information** (under your version draft).

### Sign-In Information

> "Does your app require sign-in?"

**Yes**

| Field | Value |
|---|---|
| User Name | `demo` |
| Password | `(leave blank or any value)` |

### Notes

Paste this into the **Notes** field (up to ~6,000 chars):

```
DEMO MODE WALKTHROUGH FOR APP REVIEW

To exercise the full app without spending real money or completing
Stripe identity verification, sign in with the name "demo" (any
case) on the Register screen. Email can be anything; password is
not used. This enables Demo Mode, which:

  - Adds a "FREE" demo top-up section on Top Up (Profile > Top Up).
    Reviewers can grant themselves $5, $10, $25, $50 of wallet
    credit without going through StoreKit.
  - Replaces the live Stripe Connect onboarding with a local fake-
    bank screen so reviewers can experience the "Get Paid" flow
    end-to-end without submitting real banking info to Stripe.
  - Tags the session as "DEMO MODE" in the Profile header so it's
    obvious which environment is running.

The production Apple IAP packs and real Stripe Connect onboarding
remain accessible from the same screens — Demo Mode adds bypass
options, it does not replace the real paths.

ABOUT THE BUSINESS MODEL

AI Marketplace is a storefront for AI-generated novels, music, and
film. Two user roles in one app:

  - BUYERS purchase consumable wallet credit packs via Apple In-App
    Purchase ("Tier 5/10/15/20" packs, each granting $5/10/15/20
    USD of in-app credit). They spend that credit to unlock titles
    in the marketplace catalog. Real money never leaves Apple's
    IAP rails for buyers.
  - CREATORS publish their AI-made works through the Publish flow.
    Submissions are auto-reviewed by an on-device AI Editor that
    scores quality, originality, and AI-disclosure compliance.
    Only submissions scoring 85%+ are published. Creators receive
    85% of net IAP proceeds via Stripe Connect Express payouts to
    their personal bank account. The 15% platform retention covers
    operating costs.

CONTENT MODERATION

  - Pre-publication: AI Editor rejects below-quality work and
    content matching prohibited categories (sexually explicit,
    graphic violence, hate, harassment, undisclosed-AI deception).
  - Post-publication: every title has a Report button (Reports flow
    in MediaDetailView). Reports route to the operator's in-app
    moderation queue (AdminConsole > Moderation), worked within
    24 hours.
  - Users can block individual creators from their account, hiding
    that creator's work from their Browse/Library views.
  - Operators can take down content + suspend creators from the
    admin moderation queue.

WHERE STRIPE FITS

Stripe Connect Express is used ONLY to pay CREATORS (money flowing
OUT of the platform to bank accounts). All buyer money flows
exclusively through Apple IAP. Stripe is never the buyer-side
payment method, in compliance with App Store Guideline 3.1.1.

CONTACT

If you need anything else for review, reach me at:
  mvalasek77@gmail.com

Thanks for reviewing AI Marketplace.
```

### Contact Information

| Field | Value |
|---|---|
| First Name | `Mike` |
| Last Name | `Valasek` |
| Phone | *(your number)* |
| Email | `mvalasek77@gmail.com` |

### Attachment

Optional. If you have a short demo video walkthrough (≤500 MB MP4), upload it. Otherwise leave blank.

---

## 6. Version Information (1.0)

App Store Connect → **App Store** tab → **Version 1.0** (under iOS App).

### Description (≤4000 chars)

```
AI Marketplace is the storefront for AI-made novels, music, and
film — where machine-made stories find their audience.

Every title on the marketplace was made with the help of AI tools,
and every title discloses which ones. No quiet ghostwriting, no
disguised generators. The catalog is a window into what AI can
actually create when a real person is in the driver's seat.

DISCOVER

Browse novels, songs, and short films across genres. Every title
shows the AI tools used to make it — Claude, GPT, Suno, Runway,
and more — so you always know what you're getting.

Charts surface the Top 10, the Trending titles, and the Editor's
Picks — works that scored highest on the AI Editor's 85%
commercial-quality bar.

BUY

Top up your in-app wallet with credit packs ($5, $10, $15, $20).
Apple processes every purchase. Spend credit to unlock any title
in the catalog. Re-read, re-listen, re-watch — owned titles live
in your Library forever.

PUBLISH

Anyone can publish. Submit your AI-made novel, music, or film
through the Publish flow. The AI Editor reviews every submission
against a strict 85% commercial-quality bar that scores prose,
originality, structure, and required AI disclosure. Pass the bar,
your title goes live in the catalog and starts earning.

GET PAID

Connect your bank to Stripe in five minutes. Whenever someone
buys your title, you keep 85% of the net (Apple takes its standard
App Store commission first). Payouts land in your bank account on
Stripe's regular schedule.

THE 85% BAR

The AI Editor is not a rubber stamp. It scores submissions against
a calibrated 85% commercial-quality threshold. Most submissions
don't pass on the first try — and that's the point. Work that
ships on AI Marketplace clears a bar that lets it stand next to
the best commercial releases, not below them.

DISCLOSURE

Every title's listing includes a Disclosure card naming the AI
tools used to write/compose/render it. We do not allow undisclosed
AI work, and we do not allow human work passed off as AI work.
Honesty is the floor.

MODERATION

Every title has a Report button. Reports route to the operator
moderation queue and are reviewed within 24 hours. Sexually
explicit content, graphic violence, hate speech, harassment, and
intellectual-property infringement are prohibited. You can also
block individual creators from your account.

PRIVACY

We collect only what we need to run your account, deliver your
purchases, and pay creators. No third-party ads, no analytics
SDKs, no tracking across apps. On-device data is encrypted at
rest. Account deletion is in-app (Profile > Account > Delete
Account) and removes everything.

FOR PARTNERS

Invited AI partners (Suno, Claude, GPT, Runway, Luma, Pika,
others) earn a small attribution credit on every sale of a title
that used their tools. The Partner Program is open by invitation.

ABOUT

AI Marketplace is built on the conviction that AI-made art deserves
a serious storefront — one with quality gates, honest disclosure,
clear money rules, and a path for creators to actually get paid.
This is the first version. More to come.

Have a question? Read the Support page or email mvalasek77@gmail.com.

Made with AI. Built for humans.
```

### Promotional Text (≤170 chars, editable any time without resubmitting)

```
The storefront for AI-made novels, music, and film. Every title clears the 85% quality bar. Honest disclosure, 85% to creators, Apple-backed purchases.
```

### Keywords (≤100 chars, comma-separated, **no spaces around commas**)

```
ai,marketplace,novels,music,film,creators,suno,claude,gpt,publishing,storefront,royalties,indie
```

### What's New in This Version

```
Welcome to AI Marketplace v1.0 — the first release.

• Browse AI-made novels, music, and film with full disclosure of the AI tools behind each title.
• Buy titles with Apple in-app credit packs; everything you buy stays in your Library.
• Publish your own AI-made work — the AI Editor reviews every submission against a strict 85% commercial-quality bar.
• Connect your bank to Stripe in five minutes and earn 85% of every sale you make.
• Report, block, and moderate. Every title has a Report button; reports are reviewed within 24 hours.

Feedback: mvalasek77@gmail.com
```

### Support URL

```
https://mvalasek77-droid.github.io/Mike_claw/aim/support.html
```

### Marketing URL (optional)

```
https://mvalasek77-droid.github.io/Mike_claw/aim/
```

### Copyright

```
© 2026 Mike Valasek
```

### Routing App Coverage File

Leave blank (not a routing app).

---

## 7. Screenshots (you create + upload)

App Store Connect → Version 1.0 → **App Previews and Screenshots**.

### Sizes Apple requires

| Device | Resolution |
|---|---|
| iPhone 6.7" (Pro Max class) | 1290 × 2796 |
| iPhone 6.5" (Plus class) | 1284 × 2778 *(can reuse 6.7")* |
| iPad 12.9" *(if shipping iPad)* | 2048 × 2732 |

You need **3–10 screenshots per device size.** Recommended sequence:

1. **Browse / Top 10** — hero shot of the catalog
2. **Title detail** — showing AI disclosure card + Buy button
3. **Wallet / Top Up** — showing the credit packs
4. **Publish flow** — showing the AI Editor review
5. **Partner Program / Get Paid** — showing the Stripe-connected creator dashboard
6. **Profile** — showing wallet balance + library count

Easiest workflow: launch the app in the iPhone 15 Pro Max simulator → Device > Trigger Screenshot for each → file lands on Desktop → drag into App Store Connect.

---

## 8. Build

App Store Connect → Version 1.0 → **Build** section → click **+** → select the latest TestFlight build (the one that passed Xcode Cloud).

---

## 9. App Icon

If not embedded in the build, upload a **1024 × 1024 PNG, no transparency, no rounded corners** (Apple rounds them). App Store Connect → Version 1.0 → App Icon.

---

## 10. Encryption Declaration

When you click Submit for Review, Apple asks:

> "Does your app use encryption?"

**Yes** — HTTPS for Worker calls; AES-GCM for on-device state encryption.

> "Does your app meet any of the following: Only uses exempt encryption…"

**Yes** — qualifies for exemption under the "uses only standard encryption available within the operating system" category (TLS via URLSession, CryptoKit AES-GCM, Keychain). You do not need to file an annual self-classification report.

If Apple asks for the export classification: **5D992** (standard encryption used in mass-market software).

---

## 11. Final pre-submit checks

- [ ] All sections show ✅ green in App Store Connect (no missing fields)
- [ ] The selected build for Version 1.0 is the latest tested TestFlight build
- [ ] Screenshots uploaded for at least 6.7" iPhone
- [ ] App icon uploaded (1024×1024 PNG)
- [ ] Privacy Policy URL loads (open it in a browser to verify)
- [ ] Support URL loads
- [ ] Test the demo flow once more on TestFlight — register as "demo", verify Top Up shows free packs, verify Connect Bank shows DemoStripeView

Then: **Submit for Review** button (top right of the version page).

---

## 12. After submission

- **Status: Waiting for Review** — Apple's queue. Usually 24–48 hours.
- **Status: In Review** — under active review. Usually a few hours.
- **Status: Approved** — ships at the date you set (or immediately).
- **Status: Rejected** — Apple posts a message under the **Resolution Center** tab. Common rejection reasons for marketplace apps:
  - Missing Stripe disclosure in TOU
  - UGC moderation pillars not clearly described
  - Demo credentials don't work / reviewer can't sign in

If rejected: paste Apple's message to me. I'll write the fix and/or the response in the Resolution Center.

---

*Generated for AI Marketplace v1.0. Keep this file in `docs/aim/` so it survives.*
