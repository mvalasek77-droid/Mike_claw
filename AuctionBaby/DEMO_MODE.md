# Demo Mode — for Apple App Review

Auction Baby ships a built-in Demo Mode so reviewers can exercise every
revenue-relevant flow (Gavel top-ups, Spotlight Boost, Auction Baby Pass,
the status archetypes, the full bid → match → review loop) without spending
real money or relying on a live backend.

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

## Recommended review path (≈8 minutes)

1. Launch → pick **Bid on dates** (the man side) → name `demo` → **Step
   onto the floor**. Wallet shows 25,000 Gavels; profile shows the
   **DEMO MODE · App Review** badge.
2. Browse the floor → open any profile → **Place a bid** → watch her
   (simulated) decision land. Bid on a few — one will be an AI Copycat
   and the reveal + credit hit fires (that's the app's core mechanic;
   fakes are disclosed in the house rules at onboarding).
3. Store (hammer icon) → confirm the **Demo Mode** card and the real IAP
   packs below it → tap **Free Black Card Pass** → every Pass perk
   (rank reveal, rewind, read receipts) is now unlocked.
4. Status tab → buy an archetype with Gavels (e.g. Millionaire) —
   real Gavel economics, play-money source.
5. Any Pass-gated feature → the paywall shows the demo activate button
   alongside the real subscription CTA.
6. Profile → **Reset account** → returns to onboarding, demo mode and
   the demo Pass clear. Re-register with any other name for the
   production experience.

## What is NOT bypassed

- The full auction loop — bids, decisions, matches, chat, date reviews,
  Auction Credit / Showcase scores — runs identically to production.
- Real IAP products still load and can be purchased with a sandbox
  account in the same session.
- The safety surfaces (block & report, Safety Center) are identical.
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
