# AI Marketplace — TikTok spot generator

One command. Produces `tiktok-ad.mp4`: a 1080×1920 vertical, ~17-second
commercial with stylized vehicle-crash visuals, a single voiceover line
(ElevenLabs preferred, OpenAI TTS fallback), and the slogan reveal.

## The storyboard

```
0.0 – 3.0  s   ROCKET           tall white booster on the launch pad, starfield
3.0 – 4.8  s   APPROACH         silver angular wedge truck charging in L→R, speed lines
4.8 – 5.2  s   IMPACT           front bumper hits rocket; yellow-white flash
5.2 – 6.2  s   FIREBALL         core blast eats both vehicles; debris fragments
6.2 – 8.0  s   MUSHROOM RISES   stem and cap forming; ember core
8.0 – 10.0 s   MUSHROOM FULL    cap fully bloomed; "AI Marketplace" emerges from the top
10.0 – 14.0 s  SLOGAN HOLD      "AI Marketplace · The Future is Next." on residue smoke
14.0 – 17.0 s  CTA              "Welcome to AI Marketplace · Available in the App Store"
```

Hard cuts (no crossfades) — reads more TikTok-native. The voiceover is a
single line that lands at the slogan: **"AI Marketplace. The future is next."**
The script delays the audio by 9 seconds so it arrives exactly when the
slogan appears on screen.

## What's stylized (and why)

The vehicles are deliberately **unbranded**: the truck is a generic silver
angular pickup; the rocket is a generic tall white booster. Silhouettes still
read as the recognizable real-world things — that's what makes the joke land
— but the SVG contains no trademarks, badges, or branded color schemes. That
keeps you out of trademark trouble while preserving the visual punch.

If you want to swap any of it (different vehicle, different rocket, more
debris, longer fireball), every shape is a small SVG function in
`generate.mjs` — edit and re-run.

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
The script mixes it under the voice at about −18 dB so it doesn't fight the
slogan. For this concept, a tense build-then-boom track works best — the
explosion timestamp is around 5 seconds, so a track that has a drop near
that point will lock everything together.

Output: `tiktok-ad.mp4`. Upload to TikTok. Done.

## Cost

A single run uses one short TTS call (~$0.01–0.03 on ElevenLabs Turbo). The
voiceover is one sentence, so spend per re-iteration is essentially zero.

## Suggested caption + hashtags

```
The future they promised crashed.
AI Marketplace. The Future is Next. 🍊

Novels · Music · Film — AI-made, AI-reviewed, AI-disclosed.
Link in bio.

#AIMarketplace #FutureIsNext #ChatGPT #ClaudeAI #Gemini #Grok
#GenerativeAI #AIArt #AIMusic #AIVideo #TeslaParody #SpaceXParody
#IndieDev #BuildInPublic #AppStore #FrontierAI
```

## Editing

Everything's inline in `generate.mjs`:

- `VOICEOVER` — what the narrator says (currently one line)
- `VOICE_DELAY_S` — when the voice starts (defaults to 9.0 s)
- `CARDS` — durations + which render function runs in each slot
- `rocket()`, `cyberTruck()`, `speedLines()`, `stars()`, `ground()` — shared
  scene elements; tweak coordinates or colors freely
- `cardRocketStanding` / `cardTruckApproaching` / `cardImpact` /
  `cardFireball` / `cardMushroomGrow` / `cardMushroomFull` /
  `cardSloganHold` / `cardCTA` — the individual frame compositions
- `VOICE_ELEVEN` — which ElevenLabs voice (must exist in your library)
- `BRAND` — colors are kept in sync with the app's Theme.accent

Total runtime: ~30–60 seconds wall-clock.

## Security

`.env`, `.tiktok-work/`, and the output `tiktok-ad.mp4` are gitignored.
**Never paste API keys into a chat, PR, or commit message.** If a key ever
leaks, rotate it at the provider's dashboard immediately.
