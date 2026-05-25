# AI Marketplace — Feature Roadmap

A KDP × Netflix marketplace for AI-generated novels, music and film. Creators
register work, the AI Editor gates it at an 85% commercial-quality bar, and
accepted titles go live in a cinematic store. Creators keep 85% of every sale;
the platform takes a 15% service fee.

## Shipping now (v1.0)
- KDP-style registration + per-title publishing wizard (format → details → AI
  disclosure → content upload → cover art → pricing → review).
- AI Editor: explainable rubric scored against the 85% commercial bar, with a
  pass/revise verdict and per-criterion notes.
- Netflix-style store: cinematic hero, Top 10, Trending, Just Published, and
  per-type rows; full title pages.
- Dedicated players: AVKit video, AVPlayer audio with custom transport, and a
  paginated reader with adjustable type.
- Commerce: Apple Pay + in-app wallet, 85/15 split, creator dashboard.
- Security: on-device AES-GCM encryption of account, entitlements and drafts;
  key held in the Keychain. Privacy manifest + privacy policy + terms.
- Polish: iOS 26 Liquid Glass (guarded), adaptive Core Haptics, dark mode,
  Reduce Motion support, Dynamic Type, VoiceOver labels.

## Next (v1.1–1.2)
- iCloud sync of library + watchlist across devices.
- Real creator payouts (Apple/Stripe Connect) and tax forms.
- Ratings, reviews, and personalised recommendations.
- Offline downloads for owned titles.
- Push notifications for new drops from followed creators.

## Later (v2)
- Series & seasons (episodic film, serialized novels).
- Bundles, gifting, and creator storefront pages.
- Localized AI Editor rubrics per genre and language.
- Family Sharing.

## Known limitations / for Codex to pick up
- Payments are demo-only: `PaymentService` authorises Apple Pay locally and the
  wallet is simulated. Wire to a real payment processor + server validation.
- Audio/video assets are creator/bundle supplied (see
  `Resources/Samples/README.md`); there is no streaming backend yet.
- Catalogue beyond the signed-in user's published titles is seeded sample data.
