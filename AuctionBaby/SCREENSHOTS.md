# Auction Baby — App Store screenshot shot-list

The exact frames to capture for the App Store, with captions and setup. Apple
requires **iPhone 6.9"/6.7"** screenshots (3–10). Capture in **Demo Mode**
(name = `demo`) so the floor is populated and nothing real is exposed.

Rules: no nudity, no implied transactional content, keep the compliant framing
visible. Use the **iPhone 16 Pro Max simulator** (6.9") for the required set.
`⌘S` in the Simulator saves a screenshot; or `xcrun simctl io booted screenshot
frame.png`.

Optional: add a short marketing caption band above each frame (many apps do)
using the captions below — keep text ≤ ~6 words on the band.

| # | Screen | How to reach it (Demo) | Caption band |
|---|--------|------------------------|--------------|
| 1 | **The Floor** — a lot card in view | Onboard as Bidder → floor | "Dating built on real intent" |
| 2 | **Profile detail** — photos, prompts, verified badge | Tap a lot's photo | "See the person, not just a pic" |
| 3 | **Bid composer** — amount + the "money you'll spend on the date" disclosure clearly visible | Tap **Bid** on a card | "A bid is a promise — for the date" |
| 4 | **Match / SOLD! moment** or a match row | Woman side: Summon → accept | "Match when it's mutual" |
| 5 | **Chat** — a conversation with the opener + a reaction | Open a match → send a line | "Plan a first date worth showing up for" |
| 6 | **Auction Baby Pass paywall** — tiers, prices, benefits, Terms/Privacy links | Trigger the paywall (My Bids → Upgrade) | "Go further with a Pass" |

### Must-haves before capturing
- ☐ **Frame 3** must show the date-spend disclosure text (the "money you'll
      spend on the date itself… never a payment to her" copy) — this is the
      single most important compliance frame.
- ☐ **Frame 6** must show the **price, /month, benefits, Restore, and the
      Terms + Privacy links rendered** — which means `AB_TERMS_URL` /
      `AB_PRIVACY_URL` must be set first, or the links show blank.
- ☐ No real user data anywhere (Demo Mode guarantees this).
- ☐ Status bar clean (full battery, no debug overlays). `xcrun simctl status_bar
      booted override --time 9:41 --batteryLevel 100 --cellularBars 4` gives the
      classic clean bar.

### Order to upload
Lead with Frame 1 (the hook), then 3 (the concept), then 2/5/4/6. The first
1–2 are what most users see in search results — make them the strongest.

### App preview video (optional, 15–30s)
Floor scroll → open a profile → place a bid (show the disclosure) → match →
chat. Keep it calm and clear; no claims you can't support.
