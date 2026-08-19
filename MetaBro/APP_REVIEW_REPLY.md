# App Store Connect — Guideline 2.1 Reply

## Reply to paste into App Store Connect Notes field:

---

Thank you for reviewing MetaBro. Below are the requested details:

**1. Screen Recording**

A screen recording is attached to this reply, captured on a physical iPhone 17 Pro Max running iOS 27.0. The recording demonstrates:

- App launch → Onboarding flow (welcome screen, claim handle + display name, agree to Code of Conduct)
- Post-onboarding feature tutorial (5-step walkthrough: Your Feed, Bro-hoods, Messages & Marketplace, Your Space Your Rules, Earn Bro Cred)
- Home Feed tab — scrolling feed, upvote/downvote, tap into post detail with threaded comments
- Bro-hoods tab — browsing communities, joining a community, viewing community feed
- Post composer — creating a text post, selecting a Bro-hood to post to
- Messages tab — viewing DM conversations, opening a chat, sending a message
- Profile/You tab — viewing profile, Bro Cred score, saved posts, sign out
- Safety features — tapping the ··· menu on a post to access Report, Block, and Mute options
- No paid content, subscriptions, or in-app purchases in this app
- No camera, location, contacts, or tracking permissions requested

**2. Device Models and OS Tested On**

- iPhone 17 Pro Max (iPhone18,2) — iOS 27.0
- iPhone 16 Pro Max (iPhone17,2) — iOS 26.6.1
- iPhone 17 Pro Max Simulator — iOS 26.1

**3. App Purpose and Target Audience**

MetaBro is a social platform designed for men to connect, organize, and support each other through community-based discussions. The app combines a personalized feed (upvotes/downvotes, threaded comments), topic-based communities called "Bro-hoods" (fitness, grilling, cars, fatherhood, philosophy, etc.), direct messaging, a peer-to-peer marketplace, and events/groups. The target audience is adult men (18+) seeking a positive, moderated social space with camaraderie over conflict. The app enforces a Code of Conduct during onboarding and provides community moderation tools (report, block, mute).

**4. Setup and Access Instructions**

- No login credentials required — the app runs in offline demo mode with mock data by default (METABRO_USE_LIVE=NO in build config)
- On first launch: tap "Get Bro'd In" → enter a display name and handle (e.g., "Marcus" / "ironbro") → agree to the Code of Conduct → complete the 5-step tutorial → app opens to the Home Feed
- All features are accessible immediately after onboarding — no account, email, or phone number needed in demo mode
- To test safety features: tap the ··· menu on any post or comment to access Report, Block, and Mute

**5. External Services**

- None in the current submission. The app operates entirely on-device with in-memory mock data. No external API, authentication service, payment processor, or AI service is used. A backend is planned for a future update but is not active in this version.

**6. Regional Differences**

The app functions identically across all regions. There are no region-specific features, content restrictions, or differences. All content is in English.

**7. Regulated Industry / Third-Party Material**

Not applicable. MetaBro does not operate in a regulated industry and does not include protected third-party material. All content in this version is generated mock data created by the developer.

---

## Steps to complete the resubmission:

1. ✅ Build installed on iPhone 17 Pro Max (done)
2. **Record screen capture on iPhone**: Settings → Control Center → add Screen Recording → swipe down from top-right → tap the record button → launch MetaBro → walk through: onboarding → tutorial → all 5 tabs → report/block/mute → stop recording
3. **Attach recording**: In App Store Connect → reply to the review → attach the screen recording file
4. **Paste the text above** into the Notes field
5. **Archive and upload new build** (if Apple requires a new binary — the tutorial is already in this build)