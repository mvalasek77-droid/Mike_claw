# App Store metadata

Everything App Store Connect needs.

- `app_name.txt` — display name (max 30 chars)
- `subtitle.txt` — 30-char subtitle beneath the name
- `promotional_text.txt` — 170-char rotator on the listing (editable without a new build)
- `description.txt` — full listing copy
- `keywords.txt` — 100-char comma-separated keyword line
- `whats_new.txt` — release-notes copy for v1.0
- `category_and_rating.txt` — categories, age rating rationale, ad-tracking answers, App Privacy checklist
- `screenshots.md` — 10-shot storyboard with caption + screen per position
- `review_notes.txt` — the notes to include in App Review's message box (why this is not gambling, moderation coverage, demo mode notes, contact)

## Character limits check

| File | Max | Actual |
|---|---:|---:|
| app_name.txt | 30 | 28 |
| subtitle.txt | 30 | 25 |
| promotional_text.txt | 170 | 146 |
| keywords.txt | 100 | 98 |
| review_notes.txt | 4000 | 3948 |

Keywords leave out words already in the name and subtitle (movie, box office,
opening weekend): Apple indexes those, so repeating them wastes characters.

## Submission checklist (answers Apple's Guideline 2.1 request)

Status as of Oct 3, 2026. Code is on `claude/movie-betting-app-hspuu3`, and CI
(build plus all unit and UI tests on an iPhone simulator) passes.

### Done in the repo

- [x] Written answers 2–6 in `review_notes.txt`: purpose and audience, how to use
      it (no login needed), external services, no regional differences, not a
      regulated industry
- [x] Recording shot list in `screen_recording_script.md`
- [x] App Store description, promotional text, What's New, keywords, rating notes
- [x] Screenshot storyboard in `screenshots.md`
- [x] Subscription descriptions in `../BoxCall/BoxCall/Products.storekit`
- [x] No features that don't work and no false claims: custom markets, fake
      followers and likes, and invented news are removed, and simulated traders
      are marked SIM
- [x] Mogul at $14.99 with Pro analytics, CSV export and exclusive app icons
- [x] Account deletion: Profile › Delete account and data
- [x] Reporting and blocking on every post, comment and review
- [x] Data feed refreshes on schedule; results settle on Sunday

### Build and test (you, on a Mac)

- [ ] Set `CURRENT_PROJECT_VERSION` to 2 in `../BoxCall/project.yml`, run `xcodegen generate`
- [ ] Xcode › Product › Archive › Distribute App › App Store Connect › Upload
- [ ] Install from TestFlight on a physical iPhone and test:
  - [ ] Tour, buying and closing trades, quitting and reopening the app
  - [ ] Sandbox purchase of each plan, then Restore
  - [ ] Mogul: Pro analytics, CSV export, switching the app icon
  - [ ] Sign in with Apple, then Delete account
  - [ ] Notifications, widgets, Watch app

### Apple's request

- [ ] **1. Screen recording** on a physical iPhone running the latest iOS,
      starting from tapping the app icon (follow `screen_recording_script.md`):
  - [ ] Normal flow: age check, tour, a Call, a Put, Positions, Close
  - [ ] Sign in with Apple and account deletion
  - [ ] Report, Block and Not interested on a post and a comment
  - [ ] Paywall, a sandbox purchase and Restore
  - [ ] A settled trade (buy before a Friday opening, record after Sunday)
- [ ] **2–6.** Fill in the contact line at the bottom of `review_notes.txt`
- [ ] Reply to Apple's message with the full text of `review_notes.txt` plus the video
- [ ] Paste the same text into the version's App Review Information › Notes
- [ ] Leave "Sign-in required" unchecked; no demo account is needed

### App Store Connect

- [ ] Mogul Monthly: set the price to **$14.99** and the description to
      "Pro analytics, CSV export, app icons, unlimited orders"
- [ ] Backstage and Producer's Pass descriptions: copy from `Products.storekit`
- [ ] Attach all three subscriptions to this version (Ready to Submit)
- [ ] Retake screenshots on the new build (6.7" 1290×2796 and 6.1" 1179×2556):
      the real app in use, with no news ticker, followers or custom markets
- [ ] Paste the description, promotional text, What's New and keywords
- [ ] Publish privacy policy and support pages; enter both URLs
- [ ] Age rating questionnaire and App Privacy answers from `category_and_rating.txt`
- [ ] Submit for review

### Optional

- [ ] Add `BLUESKY_HANDLE` and `BLUESKY_APP_PASSWORD` repository secrets
      (Bluesky search currently returns 403 errors)
- [ ] Add a `TMDB_API_KEY` repository secret for real posters
