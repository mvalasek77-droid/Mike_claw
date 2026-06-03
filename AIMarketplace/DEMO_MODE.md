# Demo Mode — for Apple App Review

This app ships a built-in Demo Mode so reviewers can exercise every
revenue-relevant flow (Stripe Connect onboarding, IAP wallet top-ups,
media upload, purchase, playback, payouts) without spending real money,
entering real bank details, or relying on a live backend.

## Credentials (paste into App Review Notes)

```
Demo username: Demo Reviewer
Demo email:    review@aimarketplace.demo
Password:      n/a — no password required
```

There is no real authentication step. The first screen is the
registration form. To activate Demo Mode, tap **"Continue as Demo
User · for App Review"** — the button is right below the standard
"Create account" button on the registration screen.

The app remembers the demo-mode flag across launches; reviewers don't
need to re-enable it each session.

## What Demo Mode changes

| Surface | Production behavior | Demo behavior |
|---|---|---|
| Stripe Connect | Opens Safari to Stripe Express hosted onboarding | Local "Demo Stripe setup" sheet — type any numbers, tap Complete. No data leaves the device. |
| Wallet top-up | StoreKit consumable IAP packs at $4.99 / $9.99 / $24.99 / $49.99 | Demo packs at $5 / $10 / $25 / $50 marked FREE, bypassing IAP entirely. Real IAP packs still appear below — Apple's sandbox tester can verify both. |
| Connect-account-ID | `acct_…` from Stripe | `acct_demo_<random>` set locally |
| Catalog / Editor / Publish | Identical | Identical — all real on-device analysis still runs |
| Buy a title | Wallet debited, library updated | Wallet debited, library updated (identical) |
| Reader / Player | Reads the buyer-deliverable file from Documents/published | Identical |

## Recommended review path (≈10 minutes)

1. Launch app → tap **Continue as Demo User**.
2. Browse tab → tap any title → tap **Buy** → top-up alert → **Top Up**.
3. TopUpView → tap **Demo · $25 credit** → balance jumps to $25.
4. Return to title → tap **Buy** → ownership granted → tap the play/read
   button. Confirm content plays / reads.
5. Publish tab → **Register a new title** → Stripe gate appears →
   **Set up payouts** → opens PayoutConfigView → tap **Demo: connect a
   fake bank** → enter any numbers in the sheet → **Complete demo setup**
   → Stripe status flips to "ready."
6. Back to Publish tab → wizard now passes the Stripe gate. Walk an
   8-step submission (Format → Details → AI Disclosure → Content → Cover
   → Attestation → Pricing → Review) → Submit to AI Editor → watch the
   live editor animate the real on-device passes → verdict screen shows
   **APPROVED / REJECTED** with score and suggestions.
7. If approved, tap **Publish to Marketplace** → title lands in catalogue
   (Browse → Just Published row).
8. Profile tab → confirm wallet, library, sales activity, and the
   **DEMO MODE · App Review** badge under your name.

## What is NOT bypassed

Everything that doesn't move money / leave the device is identical to
production:

- The AI Editor's content analysis runs on real bytes (NaturalLanguage
  for novels, AVAudioFile for music, AVAsset for film). The 85%
  commercial bar, gibberish detection, lorem detection, famous-IP fuzz,
  portrait-video rejection, and pricing sanity all fire identically.
- File uploads use iOS's standard `.fileImporter` — Demo Mode does not
  bypass the security-scoped URL path. Use any text / audio / video file
  on the test device.
- The Scout, Moderation queue, Admin console, and account deletion all
  behave identically.

## App Review Notes — suggested text

> This app supports a demo-mode path designed for App Review. From the
> first screen tap "Continue as Demo User · for App Review." That flag
> simulates Stripe Connect onboarding locally and exposes demo top-up
> packs that bypass IAP (the real IAP packs are still visible so the
> sandbox tester can verify the production path). Everything else —
> editor scoring, content analysis, catalog, library, playback — is
> identical to production. See DEMO_MODE.md in the repo for the
> recommended review path.

## Disabling Demo Mode after review

Demo Mode persists across launches. To exit:

1. Profile tab → Account → **Delete account** → confirm.
2. Re-register without tapping the demo button.
