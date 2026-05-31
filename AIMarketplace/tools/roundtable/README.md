# AI Marketplace — Inaugural Roundtable generator

One-shot script that records a ~25–30 minute panel episode where the four
frontier models on the marketplace introduce themselves and discuss the
future of AI media.

## What it does

For each segment, it calls the panelist's **actual model API** for the text:

| Panelist | Lab | Model id (edit in `generate.mjs` if newer ships) | Voice (OpenAI) | Voice (ElevenLabs) |
|---|---|---|---|---|
| Claude Opus 4.8 | Anthropic | `claude-opus-4-8` | `onyx` | `Brian` |
| GPT-5.5 | OpenAI | `gpt-5.5` | `ash` | `Adam` |
| Gemini | Google DeepMind | `gemini-2.5-pro` | `sage` | `Antoni` |
| Grok | xAI | `grok-4` | `fable` | `Josh` |
| Host | — | (scripted) | `nova` | `Rachel` |

Each panelist's text is then rendered through TTS with a distinct voice so the
panel sounds like four different speakers. Honest framing: the *words* are
each model's own; the *voices* are studio narrators (none of these labs ship
native audio output that you can route through an external pipeline today).

## What you need

- **Node 22+** (for native `fetch`)
- **ffmpeg** (`brew install ffmpeg`)
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

You'll see progress per segment. ~3 minutes wall-clock typically. Output:

- `inaugural-roundtable.mp3` — the episode (~25–30 MB)
- `inaugural-roundtable.txt` — full transcript with speaker labels

Cost ballpark for one full run: about **$1–3** in API spend (LLM calls + TTS).

## Ship it in the marketplace

1. Move the MP3 + a cover image into the app bundle:
   ```bash
   cp inaugural-roundtable.mp3 ../../AIMarketplace/Resources/Samples/
   cp <your-cover>.jpg ../../AIMarketplace/Resources/Samples/inaugural-roundtable.jpg
   ```
2. Add a `MediaItem` to `Store/SampleData.swift` so it shows up in the catalog
   as an Editor Original. Suggested entry:
   ```swift
   MediaItem(
       id: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!,
       title: "AI Marketplace — Inaugural Roundtable",
       creator: "AI Marketplace",
       type: .music, // closest fit — spoken-word episode
       genre: "Roundtable",
       synopsis: "The four frontier language models — Claude Opus 4.8, GPT-5.5, Gemini, and Grok — introduce themselves and discuss what AI media means right now and where the market is heading. Words from each model's own API; voices via studio TTS.",
       aiTools: ["Claude Opus 4.8", "GPT-5.5", "Gemini", "Grok", "ElevenLabs"],
       commercialScore: 92,
       price: 0.00,                       // free inaugural drop
       releaseYear: 2026,
       length: 1,                         // one episode
       maturity: "Everyone",
       purchases: 0,
       trending: 95,
       coverAssetName: "inaugural-roundtable",
       mediaFileName: "inaugural-roundtable",
       isEditorOriginal: true,
   ),
   ```
3. Regenerate the Xcode project (`xcodegen generate` in `AIMarketplace/`) so the
   new files land in `PBXResourcesBuildPhase`, then rebuild.

## Security

`.env`, `.roundtable-work/`, and the output files are gitignored. **Never
paste API keys into a chat, PR description, or commit message.** If a key
ever leaks, rotate it at the provider's dashboard immediately — keys are
the only thing standing between you and someone else's bill.
