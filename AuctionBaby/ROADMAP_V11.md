# Auction Baby — v1.1 Feature Roadmap

Target: App Store submission → WWDC-featured app quality bar

---

## Already shipped (v1.0 baseline)

| Area | Status |
|---|---|
| Sign in with Apple + Auth Worker | ✅ |
| Push notifications (APNs) + deep-link routing | ✅ |
| ID verification (Gov-ID liveness gate) | ✅ |
| Real floor / inbox / bids via Matching Worker | ✅ |
| R2 photo storage + CDN delivery | ✅ |
| Bid Insurance, Gilded Bid, Whisper Bid | ✅ |
| Lot of the Day + Art Tier rankings | ✅ |
| Gavel Confirmed (meetup check-in) | ✅ |
| Reserve the Date (calendar integration) | ✅ |
| Location-aware floor filtering | ✅ |
| Full profile editor (multi-photo, prompts, bio) | ✅ |
| Admin panel (reports, suspend, audit log) | ✅ |
| iOS 26 Liquid Glass UI + adaptive haptics | ✅ |
| ScaleButtonStyle press physics on all cards | ✅ |
| Tab badges + live inbox counts | ✅ |
| Shimmer loading states on async photos | ✅ |
| EmptyState pulse animations | ✅ |
| Reduce Motion + dark-mode compliance | ✅ |

---

## v1.1 — "Presence" (Q3 2026)

### P0 — Swipe-to-accept / swipe-to-pass
Give women a Tinder-style swipe gesture on `BidRow` so they can triage
a high-volume inbox without opening every card.

Implementation sketch:
- `DragGesture` on `BidRow` with threshold ±80 pt
- Right = accept (green checkmark reveal), left = pass (X reveal)
- Same underlying `store.acceptRemote` / `store.declineRemote` calls
- Spring-back if drag released before threshold; snap-off + remove if
  threshold crossed
- VoiceOver: add accessibility action "Accept" / "Decline" to each row

### P0 — Video prompts (replaces static photo at top of profile)
Short looping 6-second clip answers a prompt ("What I actually look like
at 7am"). Differentiated from every competitor; makes authenticity the
UX default.

Backend: presigned R2 upload URL → `video_clips` column on `profiles`
Client: `VideoPlayer(url:)` wrapped in the `AvatarView` header slot
Moderation: server-side NSFW frame-sample check before activation

### P1 — Voice intro (15 s)
One audio clip per profile. Plays automatically (muted, user taps to
unmute) on `AuctioneeDetailView`. Much lower implementation cost than
video but equally differentiating.

Backend: audio stored in R2 alongside photos (`audio_intro` column)
Client: `AVAudioPlayer` wrapper; waveform visualizer using `Canvas`

### P1 — Liveness verification (Face-matched selfie)
Extend the ID-verification flow with a real-time liveness check (device
camera → blur/motion scoring) to close the "use someone else's ID" hole.

Integration option: Apple's `Vision.VNDetectFaceLandmarksRequest` with
a blink-challenge step (no third-party SDK cost at launch)

### P1 — Background check opt-in (trust signal)
Men can pay for a background check (criminal + sex-offender registry,
US-only). Shows a "Background Checked" badge on their floor card.

Partner: Checkr API or similar; result stored as a Worker-signed claim
Badge: `BackgroundCheckedBadge` component alongside `VerifiedBadge`

### P2 — Enhanced NSFW screening
Cloudflare Images or Workers AI vision model runs on every uploaded
photo before it reaches CDN activation. Automatic decline + user warning
for explicit content; threshold-tunable from admin panel.

### P2 — Mutual interests prompt matching
Surface "You both listed Jazz" callouts on `BidRow` and `AuctioneeDetailView`
using the existing `interests: [String]` field. Cheap signal, high
perceived intelligence.

### P2 — Push notification rich media
Attach the sender's avatar (R2 thumbnail URL) to APNs `mutable-content`
payloads so iOS renders the photo in the notification banner.

---

## v1.2 — "The Market" (Q4 2026)

### Auction windows
Fixed 24-hour bidding windows instead of open-ended lots. Creates urgency,
makes the floor feel like a real auction house.

- Worker cron job closes lots at midnight local time (user TZ stored)
- "Time remaining" countdown on `FloorCard` (reuse `MatchRow` timer pattern)
- Winner auto-matches; non-winners' bids refund Insurance if purchased

### Dynamic floor pricing
Algorithmic `startingBid` suggestion based on Art Tier, location, time-on-
platform, and match rate. Shown as a pre-filled default in the profile editor.

### Referral programme
Woman refers another woman → both get a Showcase Credit bump.
Man refers another man → both get 50 Gavels.

Referral code on `MyProfileView`; tracked in a `referrals` D1 table.

### Group experiences
Two or three women can co-list a single lot (dinner party, gallery night).
Each bidder bids on the experience, not an individual.

---

## v1.3 — "Concierge" (Q1 2027)

### AI bid coach (for men)
On-device LLM (Core ML + Llama-3 distill) reads the woman's prompts and
bio and drafts a personalised bid note. User edits before sending.

### Smart re-bid suggestions
After a decline, show the bidder "Bids that won her: avg \$X, note tone:
complimentary + specific". Pull aggregate stats from the Worker.

### Women's escrow (optional, US-only)
Woman elects to hold date-spend funds in a Stripe-backed escrow during
the match window. Released on Gavel Confirmed check-in. Adds financial
safety without making the app a payment-to-person platform.

---

## Accessibility & compliance runway (every release)

- VoiceOver audit before every submission (rotors, labels, ordering)
- Dynamic Type stress-test at xxxLarge (especially `BidRow`, `FloorCard`)
- Reduce Motion pass: every animation checked for Motion.run wrapping
- EU DSA user-report acknowledgement endpoint (24-hour SLA)
- CCPA delete-my-data flow already wired; add in-app audit-log download

---

## iOS 26 Liquid Glass — ongoing refinement

GlassKit.swift already ships `GlassEffectContainer` + `.glassEffect` behind
`#available(iOS 26, *)`. As the iOS 26 SDK stabilises before GM:

- Audit every `GlassSurface` call for correct tint opacity on dark system
  backgrounds (Apple's samples use 0.04–0.08 range)
- Test `GlassEffectContainer` nesting depth — Apple recommends ≤ 2 levels
- `MatchesView` chat bubbles: consider `.glassEffect(.regular, in:
  .capsule)` for incoming messages on iOS 26
- Investigate `springLoadingBehavior` modifier for `BidSheet` spring
  physics on iOS 26+
