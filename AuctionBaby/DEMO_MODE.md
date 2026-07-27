# Demo Mode — for Apple App Review

Auction Baby ships a built-in Demo Mode so reviewers can exercise every
revenue-relevant flow (Gavel top-ups, Spotlight Boost, Auction Baby Pass,
status archetypes, dealbreaker filters, the full bid → match → date →
Gavel-Confirmed loop) without spending real money or relying on a live
backend.

## Credentials (paste into App Review Notes)

```
Name at onboarding:  demo
Password:            n/a — no password required
Everything else:     any values (age defaults to 27)
```

On the onboarding screen the reviewer picks **either side of the floor**,
enters **`demo`** (case-insensitive) as the name, and taps **Step onto the
floor**. The app recognises that exact name as the demo credential: it
enables Demo Mode for the session, swaps in the demo identity ("Demo
Reviewer"), and seeds the wallet with 25,000 Gavels. No password, no email,
no payment method.

The demo-mode flag persists across launches; reviewers don't need to
re-enable it each session.

## What Demo Mode changes

| Surface | Production behavior | Demo behavior |
|---|---|---|
| Gavel wallet | StoreKit consumable packs at $4.99–$99.99 | Seeded with 25,000 Gavels + free demo top-ups (+5,000 / +30,000). Real IAP packs still appear below — Apple's sandbox tester can verify both paths in one session. |
| Spotlight Boost | $3.99 consumable | Free demo Boost button in the store |
| Auction Baby Pass | Auto-renewable subscription ($19.99 / $39.99 / $99.99 per month) | "Demo: activate free" button on the paywall and in the store (grants the tier locally). Real subscribe buttons stay live. |
| Bidding / matches / chat / reviews | Identical | Identical — the floor is fully simulated on-device in all builds |
| Copycat reveal + Auction Credit | Identical | Identical — bid on an unlabelled AI profile and the reveal fires the same way |
| Multi-photo upload | Real PhotosPicker → encrypted on-device storage | Identical — the reviewer can add real photos or skip and get the gradient monogram fallback |
| Reserve Requirements (dealbreaker filters) | Reserve-tier gated (height / smoking / drinking / kids / education) | Gated identically; the "Demo: activate Reserve free" paywall button unlocks them |
| Whisper | Free anonymous nod, no Gavels charged | Identical |
| Bid Insurance | 200-Gavel premium; refunds + Gilded credit on decline | Identical (paid from seeded Gavels) |
| The Docket (streak-freeze + mystery box) | Standard | Identical — reviewer can watch the mystery-roll on a fresh Day 1 claim |
| The Standing (weekly leaderboards) | Standard | Identical; reviewer's demo profile appears in the "you" row |
| Lot of the Day intro | First launch of a new day | Fires once per calendar day for the demo account too |
| Status ratings (top 4) | Non-consumable IAPs, $999.99–$9,999.99 | All four marked **owned** — equip free, no charge. Real buy buttons stay live for sandbox verification. |

## Recommended review path (≈ 12 minutes)

1. **Launch** → pick **Bid on dates** (the man side) → name `demo` →
   **Step onto the floor**. Wallet shows 25,000 Gavels; profile shows the
   **DEMO MODE · App Review** badge. The **Lot of the Day** full-screen
   intro fires — dismiss with the X or tap **Place a bid** to jump into
   the composer.
2. Browse the floor → look for the pulsing green **ON THE FLOOR NOW**
   chip on ~30% of cards (deterministic per hour). Open any profile →
   scroll to see her Lifestyle card (height / smoking / drinking / kids /
   education) → **Place a bid**. In the composer, try both **Gild** and
   **Bid Insurance** toggles, then **Whisper** as the free anonymous
   alternative. Watch the sim decision land within a few seconds.
3. Bid on a few → one will be an **AI Copycat** and the reveal + credit
   hit fires (that's the app's core mechanic; fakes are disclosed in the
   house rules at onboarding).
4. Open an accepted match → chat opens with the woman's **Opening Bid
   Script** as the auto-sent first line → send a reply → **Mark date done**
   → in the review sheet, toggle **We met in person** to see the
   **Gavel Confirmed** seal on the resulting review and the credit line
   in the report card.
5. Filter icon on the floor → **Reserve Requirements** section: try to
   toggle a dealbreaker → paywall fires → tap **Demo: activate Reserve
   free** → return and see the dealbreakers filter the feed live.
6. **Store** (hammer icon) → confirm the **Demo Mode** card and the real
   IAP packs below it → tap **Free Black Card Pass** → every Pass perk
   (rank reveal, reserve-price reveal on the detail view, read receipts,
   priority placement, auto-rebid on decline) is now unlocked.
7. **Status tab** → buy a Gavel rating (e.g. **Got a Good Job**, 12,000
   Gavels) — real economics, play-money source. The four top ratings
   (Inheritance Money Guy $999.99 → Trillionaire $9,999.99) are real
   non-consumable IAPs; **Demo Mode marks all four as owned**, so tapping
   one shows "Wear this badge" and equips it free — no four-figure charge
   is ever made in Demo Mode. The real purchase buttons still appear for
   a sandbox tester who wants to verify that path.
8. **Profile → The Standing** → weekly cosmetic leaderboards for the
   demo user's city. **Profile → Edit photos** → PhotosPicker prompts
   the reviewer for photo-library access (real iOS permission), then
   pick 1–6 photos. **Profile → Opening Bid Script** (woman side only)
   → set a canned opener that auto-sends on next accept.
9. **Feed → Daily claim card** → the **Docket** row shows streak-freeze
   inventory + a buy CTA; a mystery roll can land a Gilded credit or a
   bonus streak-freeze instead of the base Gavel reward.
10. Any Pass-gated feature → the paywall shows the demo activate button
    alongside the real subscription CTA.
11. **Profile → Reset account** → returns to onboarding, demo mode and
    the demo Pass clear. Re-register with any other name for the
    production experience.

## What is NOT bypassed

- The full auction loop — bids, decisions, matches, chat, date reviews,
  Auction Credit / Showcase Credit — runs identically to production.
- Real IAP products still load and can be purchased with a sandbox
  account in the same session.
- Every dealbreaker / Pass perk / Bid Insurance / Whisper / Gavel Confirmed
  flow runs on the same code as the paid production path — Demo Mode only
  changes how the currency is *acquired*, never how it's *spent*.
- The safety surfaces (block & report, Safety Center, in-app "Report a
  bug" via mailto) are identical.
- The admin console stays locked behind founder credentials; the demo
  account cannot see or reach it.

## App Review Notes — suggested text

> This app supports a credential-driven demo mode for App Review. On the
> onboarding screen, choose either role and enter "demo" as the name,
> then continue. That activates Demo Mode for the session: the Gavel
> wallet is pre-funded, free demo counterparts of every paid product
> appear in the store, and the Pass can be activated free from the
> paywall. The real IAP products remain visible and purchasable so the
> sandbox purchase path can be verified in the same session. All profiles
> and matches are simulated; the app discloses at onboarding that AI
> "Copycat" profiles exist as part of the core mechanic. See DEMO_MODE.md
> in the repository for the full walkthrough.

## Disabling Demo Mode after review

Profile tab → **Reset account** → confirm. This clears the demo flag and
the demo Pass, and returns to onboarding.
