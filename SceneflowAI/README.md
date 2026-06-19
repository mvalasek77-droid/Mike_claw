# Sceneflow

A pro-level iOS screenwriting app that matches what Arc Studio Pro does —
industry-standard formatting, a beat board, structure templates, production
revisions, statistics, and Final Draft / Fountain / PDF interchange — and adds
an AI writing room on top. Positioned at **$24.99/year**, roughly a quarter of
the ~$99/year that comparable pro screenwriting apps charge.

> Built with SwiftUI (iOS 17+). The project is generated with
> [XcodeGen](https://github.com/yonyz/XcodeGen) from `project.yml`.

## Building

```bash
brew install xcodegen          # once
cd SceneflowAI
xcodegen generate              # produces Sceneflow.xcodeproj
open Sceneflow.xcodeproj        # build & run on an iOS 17 simulator/device
```

No third-party Swift packages — everything is SwiftUI, Charts, PDFKit/UIKit.

## What it does (Arc Studio parity + extras)

| Capability | Where |
|---|---|
| Auto-formatting editor (smart return, type cycling, smart-type autocomplete) | `Features/Editor` |
| Scene headings, action, character, parenthetical, dialogue, transitions, dual dialogue | `Models/Screenplay.swift` |
| Beat board (index cards in act columns) | `Features/BeatBoard` |
| Structure templates — Three-Act, Save the Cat, Hero's Journey | `Models/Outline.swift` |
| Outline view (beats + scene list) | `Features/Outline` |
| Live page count & runtime estimate | `Services/PaginationEngine.swift` |
| Statistics — scene mix, dialogue-by-character chart, word counts | `Features/Stats` |
| Production revisions (WGA color order, locked pages) | `Features/Revisions` |
| Character bible with voice notes | `Features/Editor/CharacterBibleView.swift` |
| Title page | `Features/Editor/TitlePageEditor.swift` |
| Import / export **Fountain** | `Services/FountainParser.swift` |
| Export **Final Draft (.fdx)** | `Services/FDXExporter.swift` |
| Export print-ready **PDF** (US-Letter Courier) | `Services/PDFExporter.swift` |

### The AI room (the differentiator)

Powered by Claude (`Services/AITools.swift`):

- **Continue Scene** — drafts the next lines in your established voice
- **Punch Up Dialogue** / **Tighten Action** — craft-level rewrites
- **Coverage Notes** — an honest reader's report (logline, strengths, concerns, next steps)
- **Generate Logline / Synopsis** — pitch material from the script
- **Brainstorm Beats** — unstuck ideas with real range
- **Check Character Voice** — flags off-voice lines using the character bible
- **Suggest Names** / **Analyze Tone**

Results can be copied or inserted straight into the script.

## Architecture

```
Sceneflow/
  App/        app entry, root routing, tab bar
  Theme/      design system (palette, type, motion, haptics)
  Models/     Screenplay, Beat, StructureTemplate, Revision, CharacterProfile
  Services/   persistence, Fountain/FDX/PDF, pagination+analytics, AI client, pricing
  Components/ reusable glass cards, buttons, pills
  Features/   Library, Editor, BeatBoard, Outline, Stats, Revisions, AI, Settings, Onboarding
  Resources/  Info.plist, asset catalog, privacy manifest
backend/      reference AI proxy (FastAPI + Anthropic SDK)
```

Persistence is one JSON file per screenplay in the app's Documents directory
(`ScreenplayStore`), with debounced autosave from the editor.

## AI security model

The app **never embeds an Anthropic API key**. A client-side key is
extractable from the binary and could be abused. Instead the app calls a thin
proxy you host (`backend/proxy.py`), which holds the key server-side and calls
the Claude Messages API. Set the proxy URL in **Settings → AI Backend**. Until
it's set, the AI room runs in clearly-labelled demo mode so the UI is still
explorable.

The reference proxy defaults to **Claude Opus 4.8** with adaptive thinking and
an effort dial mapped from the app's "creativity" setting, and it handles the
`refusal` stop reason gracefully.

## Pricing

| | Sceneflow Pro | Comparable pro apps |
|---|---|---|
| Annual | **$24.99** | ~$99 |

Free tier: unlimited projects, full editor, beat board, Fountain I/O, and 10 AI
assists per month. Pro unlocks unlimited AI, Final Draft + PDF export,
production revisions, and the character bible. Real billing is wired through
StoreKit 2 at ship time; `Entitlements` models the gating today.

## Notes / next steps

- Wire `Entitlements.unlockPro()` to a StoreKit 2 product (`pro.annual`).
- Add streaming to the AI proxy + app for token-by-token output.
- Real-time collaboration (Arc Studio has it) would need a sync backend; the
  document model is already value-typed and Codable to support it.
- Add an `AppIcon` 1024² asset before submission.
