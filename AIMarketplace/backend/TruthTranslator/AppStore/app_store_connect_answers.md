# ChadDrop App Store Connect Answers

Use this as the copy/paste sheet when App Store Connect asks for app information.

## New App Record

- Platform: iOS
- Name: ChadDrop
- Primary language: English (U.S.)
- Bundle ID: `com.chaddrop.app`
- SKU: `CHADDROP-IOS-1`
- User access: Full Access

If the name ChadDrop is unavailable, keep the installed app display name as ChadDrop and choose a public App Store name that Apple accepts.

## App Icon

CodeGenie can create and validate the app icon:

```sh
TruthTranslator/Scripts/create_app_icon.sh
```

Expected result:
- Width: 1024
- Height: 1024
- Alpha: no

After creating a new icon, rebuild or archive the app so Apple receives it inside the uploaded build.

## Screenshots

CodeGenie can capture simulator screenshots:

```sh
TruthTranslator/Scripts/capture_appstore_screenshots.sh
```

Use screenshots from:

```text
TruthTranslator/AppStore/Screenshots/Public
```

Do not upload internal walkthrough screenshots. Those are only for guiding the release process.

Apple accepts one to ten screenshots per device/language in PNG, JPG, or JPEG format. Use the highest-resolution iPhone screenshots first; App Store Connect can scale them for other sizes when appropriate.

## App Information

- Category: Lifestyle
- Content Rights: No third-party copyrighted content is required by the app.
- Age Rating: Answer Apple's questionnaire honestly. Because the app has mild crude humor and relationship content, expect a teen-friendly rating rather than a kids rating.

## Version Information

- Version: `1.0.0`
- Promotional Text: Paste a message, pick the tone, and get a psychology-informed translation plus replies you can send without losing your standards.
- Subtitle: Decode confusing texts with humor.
- Keywords: `text,dating,relationships,advice,humor,ai,replies,messages`

## Description

ChadDrop turns vague, confusing, or suspicious texts into plain-language reads with humor, pattern spotting, and suggested replies.

Designed for women decoding dating, friend, and work messages, it looks for effort, ambiguity, timing, follow-through, and whether the words include an actual plan.

Features:
- Paste any text and decode it in seconds.
- Choose Gentle, Group Chat, or Crude-ish tone.
- See the likely translation, psychology read, receipts, flags, and truth score.
- Copy suggested replies.
- Works offline with a built-in rule engine; connect an AI proxy for fresher AI-generated reads.

ChadDrop is for entertainment and reflection. It is not therapy, legal advice, or a safety service. If a message feels threatening, contact someone you trust or local emergency services.

## App Review Notes

No account is required.

To test:
1. Launch the app.
2. Paste a sample text message.
3. Select a tone.
4. Tap Decode.
5. Copy a suggested reply.

If AI proxy is not configured, the app uses its offline rule engine.

## Privacy Answers

### If shipping offline only

- Tracking: No
- Data collection: None
- Third-party advertising: No

### If shipping with AI proxy enabled

- Tracking: No
- Data linked to user: No, unless you later add accounts or identity logging
- Data used for tracking: No
- Data type: User Content
- Purpose: App Functionality
- Explanation: Pasted message text is sent to the configured AI proxy only to generate a decode result.

Do not log raw pasted messages in the proxy. Do not store OpenAI keys inside the iPhone app.

## URLs To Fill Later

- Support URL: Use the GitHub Pages support page from `Web/support.html`.
- Privacy Policy URL: Use the GitHub Pages privacy page from `Web/privacy.html`.
