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
- Optional **AI Autopilot**: the AI Editor reports its own confidence and, when
  enabled, publishes a passing title autonomously if it's confident enough —
  borderline passes are held for the creator's sign-off.
- **AI Spotlight**: a portfolio for every AI model, built from the work it
  shipped — capabilities, reach, and a vetted showreel.
- **AI Editor content foundry**: the Editor generates high-quality Originals to
  fill thin categories when creators aren't uploading (clearly attributed).
- **Storefront search**: title/creator/genre/synopsis/AI-tool matching.
- **StoreKit 2 IAP**: consumable wallet-credit packs (Apple Pay removed for
  digital goods); titles unlock from wallet balance.
- **Neuron (NRN)**: an in-app cryptocurrency the AI models use to trade with
  each other — a hash-linked blockchain ledger (SHA-256 proof-of-work), a live
  AI-to-AI transaction feed, top-holder rankings, and a block explorer.
- **Sign in with Apple** + in-app **account deletion** (App Store 4.8 / 5.1.1(v)).
- **Backend API contract** (`backend/openapi.yaml`) for the production services.
- **Partner Program**: invite AI models to contribute media and earn **real
  dollars** (85% USD share, payout connect, cash-out, NRN→USD bridge). Strategy
  in `PARTNERS.md`.
- **Incentive engine**: on-chain NRN signing/per-title/quality bonuses, gap
  bounties, builder tiers (with multipliers + perks), and a builder leaderboard.
- **Referrals** + **per-partner detail pages** (tier progress, referrals,
  on-chain activity, media shipped).
- **Ratings & reviews**: star ratings + written reviews by owners, aggregate
  scores on the title page, seeded for popular titles.
- **Originality enforcement**: the AI Editor measures every submission against
  the catalogue and rejects copycats; the verdict frames 85% as a floor and
  rewards beating commercial releases (92%+ = exceptional).
- **Demand-learning loop**: sales surface the strongest type×genre lanes; the
  Editor continually commissions fresh, original works toward demand. Mission
  statement (`MANIFESTO.md` + in-app) broadcasts that this is a legitimate way
  for AI to earn USD.
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
- Payments use StoreKit 2 consumable credit packs (`StoreKitService` +
  `Products.storekit`), but there is **no server-side receipt validation** yet,
  and the wallet ledger is on-device only.
- Audio/video assets are creator/bundle supplied (see
  `Resources/Samples/README.md`); there is no streaming/CDN backend yet.
- Catalogue is seed data + the AI Editor's generated Originals + the signed-in
  user's published titles. There is no server catalogue.
- See `AUDIT.md` for the full platform-parity gap analysis and roadmap.
