# AI Marketplace — TikTok spot generator

One command. Produces `tiktok-ad.mp4`: a 1080×1920 vertical, ~25-second
commercial with a voiceover (ElevenLabs preferred, OpenAI TTS fallback) and
six hard-cut frame cards. Hard cuts, not crossfades — they read more
TikTok-native and post-edit faster.

## What you need

- **Node 22+**
- **ffmpeg** (`brew install ffmpeg`)
- **macOS** (uses built-in `qlmanage` to render SVG → PNG, zero installs)
- **ElevenLabs API key** (preferred) or OpenAI key for the voiceover

## Run

```bash
cd AIMarketplace/tools/tiktok
cp .env.example .env   # paste ELEVENLABS_API_KEY (or OPENAI_API_KEY)
node generate.mjs
```

Optional: drop a music bed by setting `BG_MUSIC=/path/to/track.mp3` in `.env`.
The script mixes it under voice at about −18 dB so it doesn't fight the VO.

Output: `tiktok-ad.mp4`. Upload to TikTok. Done.

## Cost

A single run uses one TTS call (~$0.02–0.05 on ElevenLabs Turbo, similar on
OpenAI TTS). No LLM spend.

## Suggested caption + hashtags

```
Four AIs walked into a marketplace 🎙️
Opus 4.8 · GPT-5.5 · Gemini · Grok — all making content. Novels, music, film.
AI-made, AI-disclosed, reviewed by an on-device Editor at an 85% bar.
Link in bio. 🍊

#AIMarketplace #ChatGPT #ClaudeAI #Gemini #Grok #GenerativeAI
#AIArt #AIMusic #AIVideo #AIWriting #IndieDev #BuildInPublic
#AppStore #FrontierAI #Storytelling
```

## Editing

Edit anything inline in `generate.mjs`:

- `VOICEOVER` — what the narrator says
- `CARDS` — durations + which card function runs in each slot
- `cardHook` / `cardPanel` / `cardContent` / `cardEditor` / `cardSplit` /
  `cardCTA` — the SVG for each frame (concise template literals)
- `VOICE_ELEVEN` — which ElevenLabs voice (must exist in your library)
- `BRAND` — colors (kept in sync with the app's Theme.accent)

Total runtime: ~30–60 seconds wall-clock.
