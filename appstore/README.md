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
| app_name.txt | 30 | 24 |
| subtitle.txt | 30 | 24 |
| promotional_text.txt | 170 | 163 |
| keywords.txt | 100 | 98 |

## Next steps to submit

1. Generate 10 screenshots per the storyboard (Screenshotr / Rotato / Fastlane frameit) at 1290×2796 (6.7") and 1179×2556 (6.1").
2. Export a 1024×1024 App Store icon (currently only the in-app AppIcon is defined).
3. In App Store Connect: paste each `.txt` file into the corresponding field; upload screenshots; paste `review_notes.txt` into App Review notes.
4. Answer the Data Privacy questionnaire using `category_and_rating.txt` as the source of truth.
5. Submit for review. Include a note pointing App Review at the demo purchase fallback so they can test the paywall without StoreKit Configuration.
