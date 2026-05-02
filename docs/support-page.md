# BareClaw Support

**Contact:** support@bareclaw.app
*(replace with your actual support email before publishing)*

---

## Getting started

### What is BareClaw?
BareClaw is a personal AI companion app for iPhone. You choose a companion personality, add your interests, and build a bond through conversation, music, and journaling. The companion learns your patterns over time and becomes more personal as the relationship develops.

### Do I need an account?
No. BareClaw requires no sign-in and no BareClaw account. Everything is local to your device.

### Do I need an API key?
Yes, to chat with your companion you need a **Claude API key** from Anthropic (anthropic.com). The key is entered in Settings > AI Engine. Claude offers free API credits to get started.

For the neural voice feature, a separate **ElevenLabs API key** is needed (elevenlabs.io). This is optional — the companion works without voice.

---

## Common questions

### The companion isn't responding
1. Open Settings > AI Engine and check that your Claude API key is entered and valid.
2. Tap "Check Status" — if it shows an error, your key may have expired or run out of credits.
3. Log in to console.anthropic.com to recharge or renew your credits.
4. If the key is valid but chat still fails, force-quit the app and reopen it.

### Voice isn't working / sounds robotic
1. Open Settings > Neural Voice and confirm your ElevenLabs API key and voice IDs are entered.
2. Each companion needs a unique ElevenLabs voice ID. Generic or incorrect IDs produce robotic output.
3. Check your ElevenLabs account has available characters.
4. If voice cuts out during Him/Her Mode, check that your device volume is up and the silent switch is off.

### Him/Her Mode stopped listening
Him/Her Mode requires the microphone permission to be granted. If it stops:
1. Tap the floating bear icon to check its status.
2. Go to iPhone Settings > Privacy & Security > Microphone and confirm BareClaw is allowed.
3. In the app, tap the bear icon and press Activate to restart the listener.
4. The mode includes a watchdog that automatically restarts if it goes silent — allow up to 90 seconds.

### How do I unlock Him/Her Mode?
Him/Her Mode unlocks automatically when your bond score reaches 61 points. Build your score by having meaningful conversations, logging dreams, and engaging regularly with your companion. The progress bar on the home screen shows your current score.

### How do I change my companion?
Go to the Profile tab and tap your companion's portrait, or open Chat and tap the companion name at the top to switch. Switching companions does not erase your bond history with other companions.

### How do I add a photo for my companion?
Go to Profile, tap your companion's portrait, then tap the camera icon that appears. Choose a photo from your library. The photo is stored only on your device.

### How do I delete my data?
All data is stored on your device. Deleting the app removes all chat history, journal entries, memories, interests, bond history, and companion settings. There is no BareClaw server to contact.

---

## Him/Her Mode explained

Him/Her Mode is an optional always-present companion layer that unlocks at a high bond score. When active, a floating bear icon appears over every screen. The companion:

- Listens for its wake word (your companion's name) via on-device speech recognition
- Can detect elevated stress or loud ambient sounds and offer a gentle check-in
- Checks in at natural quiet moments based on patterns it has learned

**Audio privacy:** All audio is processed on-device by Apple's Speech Recognition framework. BareClaw does not record, store, or transmit audio.

To pause Him/Her Mode: tap the bear icon and select Pause. To stop it permanently: go to Settings and deactivate it.

---

## Privacy and data

BareClaw is local-first. All conversation history, memories, journal entries, interests, and settings are stored on your device and are not sent to any BareClaw server.

When you use a third-party provider (Claude, ElevenLabs), your messages are sent to that provider under your own account. See our [Privacy Policy](/privacy) for full details.

---

## Reporting a bug

If you encounter a crash or unexpected behavior:
1. In the app, go to Chat > Settings (gear icon) > Report a Bug.
2. Describe what happened and tap Send.

Or email **support@bareclaw.app** with a description, your iPhone model, and iOS version.

---

## Legal

[Terms of Use](/terms) · [Privacy Policy](/privacy)

BareClaw is AI-generated software. Companion responses are not from a real person and must not be used for medical, legal, financial, emergency, or professional advice.
