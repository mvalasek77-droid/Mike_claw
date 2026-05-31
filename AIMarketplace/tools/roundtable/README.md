# AI Marketplace — Inaugural Roundtable generator

One command, plug and play. Produces a ~25–30 minute panel episode where the
four frontier models on the marketplace introduce themselves and discuss the
future of AI media, **with the cover art rendered and dropped into the app
bundle automatically**.

## What it does

For each segment, it calls the panelist's **actual model API** for the text:

| Panelist | Lab | Model id (edit in `generate.mjs` if newer ships) | Voice (OpenAI) | Voice (ElevenLabs) |
|---|---|---|---|---|
| Claude Opus 4.8 | Anthropic | `claude-opus-4-8` | `onyx` | `Brian` |
| GPT-5.5 | OpenAI | `gpt-5.5` | `ash` | `Adam` |
| Gemini | Google DeepMind | `gemini-2.5-pro` | `sage` | `Antoni` |
| Grok | xAI | `grok-4` | `fable` | `Josh` |
| Host | — | (scripted) | `nova` | `Rachel` |

Each panelist's text is then rendered via TTS with a distinct voice so the
panel sounds like four different speakers. Honest framing: the *words* are
each model's own; the *voices* are studio narrators (none of these labs ship
native audio output that can be routed through an external pipeline today).

## What you need

- **Node 22+** (for native `fetch`)
- **ffmpeg** — `brew install ffmpeg`
- **xcodegen** — `brew install xcodegen` (so the script can re-wire the new
  files into the Xcode project automatically; if missing, the script tells you
  what to run by hand)
- **macOS** for cover rendering — uses built-in `qlmanage` + `sips`, no extras
- **At least one panelist API key** + a TTS key. If a panelist's key is missing
  the script honestly skips that segment rather than fake it.

## Setup

```bash
cd AIMarketplace/tools/roundtable
cp .env.example .env   # then paste keys into .env (gitignored)
```

`.env` keys:

```
ANTHROPIC_API_KEY=…
OPENAI_API_KEY=…       # also acts as TTS fallback
GOOGLE_API_KEY=…       # from aistudio.google.com → Get API key
XAI_API_KEY=…          # from console.x.ai
ELEVENLABS_API_KEY=…   # optional; preferred over OpenAI TTS if set
```

## Run

```bash
node generate.mjs
```

That's it. The script:

1. Generates each panelist's text via their own API.
2. Renders each segment to audio (ElevenLabs preferred; OpenAI TTS fallback).
3. Stitches the segments into `inaugural-roundtable.mp3` with ffmpeg.
4. Writes a transcript to `inaugural-roundtable.txt`.
5. Renders `cover.svg` → `inaugural-roundtable.jpg` (1024×1024) via Quick Look + sips.
6. Copies the `.mp3` + `.jpg` into `AIMarketplace/Resources/Samples/`.
7. Runs `xcodegen generate` so the new files land in the build phase automatically.

Then:

```bash
cd ../..
open AIMarketplace.xcodeproj
# Cmd+R to build & run
```

First launch shows the **Inaugural Launch Sheet** with the four panelist chips
and a big "Listen now" button. The hero banner on Home also features the
episode (because `trending: 99` makes it the `featured` item).

## Cost ballpark

About **$1–3** per run (LLM calls + TTS). Re-runs are cheap.

## Editing the cover

`cover.svg` is plain SVG — edit colours, layout, or labels in any vector
editor or text editor, then re-run `node generate.mjs` and it re-renders the
JPG and drops it back in.

## Security

`.env`, `.roundtable-work/`, and the output `.mp3`/`.jpg` are gitignored.
**Never paste API keys into a chat, PR, or commit message.** If a key ever
leaks, rotate it at the provider's dashboard immediately — keys are the only
thing standing between you and someone else's bill.
