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
| review_notes.txt | 4000 | 3977 |

Keywords leave out words already in the name and subtitle (movie, box office,
opening weekend): Apple indexes those, so repeating them wastes characters.

## How to respond to Apple (Guideline 2.1 – Information Needed)

Status as of Oct 6, 2026. Code is on `claude/movie-betting-app-hspuu3`, and CI
(the build plus every unit and UI test on an iPhone simulator) passes.

Apple asked for six things: (1) a screen recording, (2) the app's purpose and
audience, (3) how to use it, (4) external services, (5) regional differences,
and (6) regulated-industry material. Answers 2–6 are written in
`review_notes.txt`; the recording is yours to shoot.

### Already done in the repo

- [x] Answers 2–6 in `review_notes.txt` (3,977 of 4,000 characters)
- [x] Recording template with this week's dates in `screen_recording_script.md`
- [x] Description, promotional text, What's New, keywords, age-rating notes, screenshot storyboard
- [x] Subscription descriptions in `../BoxCall/BoxCall/Products.storekit`
- [x] Tutorial, store copy and review notes match what the app does
- [x] Account deletion, plus Report / Block / Not interested on every post, comment and review
- [x] Sunday results settle automatically, including in the background

### Step 1 — Build (Mac)

- [ ] In `../BoxCall/project.yml` set `CURRENT_PROJECT_VERSION` to 2 (one higher than the last upload), then run `xcodegen generate`
- [ ] Xcode › Product › Archive › Distribute App › App Store Connect › Upload
- [ ] Wait for the build to finish processing in App Store Connect › TestFlight

### Step 2 — Test on your iPhone (TestFlight)

- [ ] Tour, buy a Call and a Put, Close one, force-quit and reopen
- [ ] Sandbox purchase of each plan, then Restore purchases
- [ ] Mogul: Pro analytics, CSV export, switching the app icon
- [ ] Sign in with Apple, notifications, widget, Watch app
- [ ] Hold a trade over a weekend and check it settles with a payout notification

### Step 3 — Record (follow `screen_recording_script.md`)

- [ ] Session A, any day before Thu Oct 8 midnight: launch → age check → tour → Call → Put → Positions → Close → reopen → leaderboard → moderation → paywall and sandbox purchase → Restore → Sign in with Apple
- [ ] Session B, Sunday Oct 11 after about 3 PM ET: the settled trade, then Delete account and data
- [ ] Join the clips without cutting steps 1–3; keep the file under 500 MB

### Step 4 — Fill in and send

- [ ] Replace `[YOUR NAME] - [YOUR EMAIL] - [YOUR PHONE]` at the bottom of `review_notes.txt` (keep it under 4,000 characters)
- [ ] App Store Connect › your app › App Review › open Apple's message › Reply: paste all of `review_notes.txt` and attach the video
- [ ] Paste the same text into your version › App Review Information › Notes
- [ ] Leave "Sign-in required" unchecked: no demo account is needed
- [ ] Select the new build (build 2) on the version page

### Step 5 — App Store Connect listing

- [ ] Mogul Monthly: price **$14.99**, description "Pro analytics, CSV export, app icons, unlimited orders"
- [ ] Backstage and Producer's Pass descriptions: copy from `Products.storekit`
- [ ] Attach all three subscriptions to this version (status Ready to Submit)
- [ ] Screenshots from the new build: 6.7" (1290×2796) and 6.1" (1179×2556)
- [ ] Description, promotional text, What's New and keywords from this folder
- [ ] Privacy policy and support pages published; both URLs entered
- [ ] Age-rating questionnaire and App Privacy answers from `category_and_rating.txt`
- [ ] Submit for review

### Optional

- [ ] `BLUESKY_HANDLE` and `BLUESKY_APP_PASSWORD` repository secrets (Bluesky search returns 403 without them)
- [ ] `TMDB_API_KEY` repository secret for real posters
