# Reply to App Review — Guideline 2.1(a), Submission 1.0 (5)

Paste the reply below into App Store Connect > App Review (Resolution Center) after the next build with this fix is uploaded.

---

Hello App Review team,

Thank you for flagging the frozen subscribe screen on iPhone 17 Pro Max / iOS 27.2.1. I reproduced the issue, identified the cause, and the fix is in the next build.

**What was happening**

BoxCall doesn't have a top-level "Subscribe" tab — subscriptions live behind the **Upgrade** button on the Profile tab, which opens a modal with the three subscription plans. That screen tries to fetch the three StoreKit products at the moment it appears. On your review device, the IAPs attached to this submission were still in review themselves, so `Product.products(for:)` returned an empty set. The screen then showed each plan's fallback price and a Subscribe button, but tapping Subscribe only wrote to an internal `lastError` field that nothing on screen rendered — so the taps appeared to do nothing.

**What I changed in the next build**

1. The subscribe screen now shows an explicit loading state while StoreKit is fetching.
2. If the fetch comes back empty or fails, the screen shows a clear "Subscriptions are unavailable right now" card with a **Retry** button, instead of a plan card with a non-functional Subscribe button.
3. When a plan hasn't loaded, its Subscribe button is replaced with a disabled "Unavailable" button, so no tap is ever silent.
4. Any error — a timeout, a StoreKit failure, a declined purchase — now surfaces as an alert the user can dismiss.
5. The Close button in the top-left of the screen was already present, and I kept it active in every state so the screen can always be dismissed back to the Profile tab.
6. The product fetch now has a 12-second ceiling. If the App Store doesn't respond within that window, the screen shows the retry card instead of hanging.

**How to reproduce the fix**

1. Open BoxCall, pass the age gate, and finish the quick tour (or skip it).
2. Tap the **Profile** tab (far right), then tap the orange **Upgrade** button in the membership card near the top.
3. Watch the subscribe screen appear with a loading spinner, then either load the three plans (Backstage, Producer's Pass, Mogul) with working Subscribe buttons, or fall back to the "Subscriptions are unavailable" card with a Retry button and a working Close button.
4. Close brings you back to Profile. The rest of the app is reachable from every state.

Thank you for the second look.

Mike Valasek
Developer, BoxCall
mvalasek77@gmail.com
