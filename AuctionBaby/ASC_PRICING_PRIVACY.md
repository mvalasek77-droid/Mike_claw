# ASC — Pricing & Availability + App Privacy (fill-in guide)

Exact answers for the two ASC sections, grounded in what Auction Baby actually
collects (verified against the code + `legal/privacy.html`). Two headline facts
that make this easy:
- **No tracking** (no ad SDK, no IDFA) → **no App Tracking Transparency prompt**, "Used for Tracking = No" everywhere.
- **No precise location, no payment/card data** collected by us (Apple handles payment; "location" is free text you type).

---

# PART 1 — Pricing and Availability

ASC → your app → **Pricing and Availability** (or **Availability** + **Pricing**
on the newer layout).

1. **Price:** **Free** (Price Schedule → base price **USD 0 / Free**). The app is
   free; all revenue is via in-app purchases.
2. **Availability:** **All countries and regions** is the simplest (recommended).
   *(A 17+ dating app is fine in most storefronts; if you want to exclude any
   market, deselect it here.)*
3. **Pre-Orders:** Off.
4. **Distribution:** Public on the App Store (not Unlisted).
5. **License / EULA:** either accept Apple's **Standard EULA**, or paste your
   custom EULA — see Part 3.

> IAP prices are set per-product, not here — see `ASC_IAP_SETUP.md`.

---

# PART 2 — App Privacy (the nutrition label)

ASC → your app → **App Privacy** → **Get Started / Edit**.

### 2.0 Setup
- **Privacy Policy URL:** `https://mvalasek77-droid.github.io/Mike_claw/auctionbaby/privacy.html`
  *(must be live — see runbook Step 2; must be filled, not the bracket draft)*.
- First question: **"Do you or your third-party partners collect data from this
  app?"** → **Yes**.

### 2.1 Data types to mark **COLLECTED** — all: Linked to identity = **Yes**, Used for tracking = **No**

| Apple category → data type | Purpose(s) to select | Why (source) |
|---|---|---|
| **Contact Info → Name** | App Functionality | Profile name + Sign in with Apple |
| **Contact Info → Email Address** | App Functionality | Sign in with Apple (incl. Hide-My-Email relay) |
| **User Content → Photos or Videos** | App Functionality | Profile photos |
| **User Content → Other User Content** | App Functionality | Bio, prompts, interests, messages, bids, reactions |
| **Identifiers → User ID** | App Functionality; Fraud Prevention | Server user id + `appAccountToken` (routes wallet/refunds) |
| **Identifiers → Device ID** | App Functionality | APNs push token (only if notifications enabled) |
| **Purchases → Purchase History** | App Functionality | Subscriptions, Gavels, status items |
| **Diagnostics → Crash Data** | App Functionality | Error/crash info to keep the service working |
| **Diagnostics → Other Diagnostic Data** | App Functionality | Device model, OS/app version, limited diagnostics |

For **each** of the above, when ASC asks:
- "Is this data used to track you?" → **No**
- "Is this data linked to the user's identity?" → **Yes**
- "What is it collected for?" → pick the purpose(s) in the table (mostly **App Functionality**)

> **Verification/face data is NOT collected.** Per the policy, Vision processes
> camera frames on-device and discards them; only a numeric score + pass/fail
> status is stored (that status rolls up under "Other User Content" / App
> Functionality). So do **NOT** declare Sensitive Info or biometric data.

### 2.2 Data types to mark **NOT collected** (say No / leave unchecked)
- **Financial Info → Payment Info** — No (Apple processes payment; we never see the card).
- **Location → Precise Location** — No.
- **Location → Coarse Location** — No. *("Location" is free text the user types, not device location.)*
- **Health & Fitness** — No.
- **Sensitive Info** — No. *(No orientation/religion/etc. fields collected.)*
- **Contacts** — No.
- **Browsing History / Search History** — No.
- **Usage Data → Product Interaction / Advertising Data** — No *(no analytics or ad SDK)*.
- **Diagnostics → Performance Data** — optional; only check if you add perf metrics. Default No.

### 2.3 The account questions (required)
- **"Does your app support account creation?"** → **Yes** (Sign in with Apple).
- **"Does your app offer account deletion?"** → **Yes** (Settings → **Delete
  account permanently**, which wipes profile/bids/matches/messages server-side).
- Provide the deletion path if asked: *Settings → Delete account permanently.*

### 2.4 What the summary should read as
- **Data Used to Track You:** *None.*
- **Data Linked to You:** Contact Info, User Content, Identifiers, Purchases, Diagnostics.
- **Data Not Linked to You:** *(none required — everything above is linked)*.

---

# PART 3 — Related fields you'll hit nearby

- **Privacy Policy URL** (App Information): the same hosted `privacy.html`.
- **License Agreement** (App Information): Apple Standard EULA, or paste your
  finalized EULA (`legal/eula.html`). Custom EULA needs the finalized text.
- **Age Rating** (separate from privacy): set **17+**; answer the questionnaire —
  Mature/Suggestive Themes = Frequent/Intense as appropriate; **no** simulated
  gambling, **no** real-money gambling. (Bidding is not gambling — it's a stated
  spend on a real date, no chance-based payout.)
- **Content Rights:** **Yes**, contains/uses third-party (user-generated) content.

---

# PART 4 — Keep it consistent (Apple cross-checks these)
The nutrition label must match the **Privacy Policy**. Your policy already
declares exactly this set (name/email, photos+content, verification-scores-only,
purchases, diagnostics, identifiers, "no precise GPS," Apple/Cloudflare/Stripe
as processors). If you change what the app collects, update **both**.

## One-screen recap
```
Price:            Free (IAP inside)
Availability:     All countries (your call)
Tracking:         None  → no ATT prompt
Precise location: Not collected
Payment/card:     Not collected (Apple handles it)
Face/biometric:   Not collected (on-device, discarded)
Linked to you:    Name, Email, Photos, Other Content, User ID, Device ID,
                  Purchase History, Diagnostics — all "App Functionality"
Account create:   Yes (Sign in with Apple)
Account delete:   Yes (Settings → Delete account permanently)
```
