# CodeGenie

> Build your next iOS app from your phone.
>
> CodeGenie wires Claude, GPT-5, your iPhone, and your Mac's Xcode together
> so you can ship to the App Store from your phone. It lives in your pocket,
> while a terminal runner on your Mac handles the Apple-only build steps.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      iOS app (this repo: ios/)                  │
│   Onboarding ▸ Home ▸ Describe ▸ Build (BitDrop) ▸ Preview ▸   │
│   App Store Connect walkthrough                                 │
└──────────────────┬──────────────────────────────────────────────┘
                   │  HTTPS + SSE
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│             Backend (this repo: backend/genie_swarm/)           │
│   FastAPI routes /api/coding/swarm/* ─→ SwarmOrchestrator       │
│                                                                 │
│   Build layer (parallel):                                       │
│     🏗️ Architect  →  💻 Coder  ∥  🎨 Designer  →  🔗 Integrator │
│                                                                 │
│   Test layer (parallel):                                        │
│     🧪 Unit Tester  📱 UI Tester  👁️ Reviewer  🔒 Security       │
│                                                                 │
│   Each agent = ConversationRuntime + sandboxed tools            │
└──────────────────┬──────────────────────────────────────────────┘
                   │  local Wi-Fi pairing
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│          Mac Terminal Runner (this repo: mac_terminal_runner/)  │
│   codegenie-terminal-runner · xcodebuild · simctl · Safari      │
└─────────────────────────────────────────────────────────────────┘
```

## What's borrowed from where

| Inspiration   | What we lifted                                                      |
|---------------|---------------------------------------------------------------------|
| **Claw Code** | Project foundation: lottery-style obsession with iterating to a green build, the "never give up" multi-step orchestration ethos. |
| **Claude Code** | `ConversationRuntime` tool-use loop, the Edit/Read/Write tool shape, sandbox boundary, hooks for state changes. |
| **Cursor**    | Parallel agent execution (Coder ∥ Designer in the build layer; all four test agents in parallel), inline diff preview before apply, head-to-head model ranking. |
| **Codex**     | Sandboxed shell with RSS / wall-clock / output caps, network deny-by-default, test-gated promotion (no ship until tests pass). |

## Run it locally

```bash
cd backend
pip install -r genie_swarm/requirements.txt
export ANTHROPIC_API_KEY=…
uvicorn app:app --reload    # mounts genie_swarm.api.router
```

Then start the Mac-side terminal runner from the repo root:

```bash
cd /path/to/CodeGenie/mac_terminal_runner
swift run codegenie-terminal-runner
```

On the phone, open **Settings → Pair your Mac**, paste the
`codegenie://pair?...` URL printed in Terminal, and tap **Start a new build**.

## File map (ios/CodeGenie)

```
App/         CodeGenieApp + AppSession (route + recent jobs)
Theme/       Liquid Glass, Haptics, Typography
Components/  PrimaryButton, GlassCard, ProgressOrb
Models/      AppDescription, BuildJob, AppStoreMetadata
Services/    Builder (sim runner), RemoteRunnerSession (live preview)
Features/
  Onboarding/         Cartoon slideshow (7 steps)
  Home/               Hero + quick grid + recent jobs + checklist
  XcodeGuide/         Pocket Xcode reference (9 steps + cheat sheet)
  Builder/            DescribeAppView + BuildScreen
  BuildGame/          BitDropEngine + BitDropView (Tetris-with-Swift-glyphs)
  RemoteBuild/        Streamed simulator preview
  AppStoreConnect/    10-step walkthrough
```

## File map (backend/genie_swarm)

```
__init__.py        Public surface
models.py          Pydantic types
streaming.py       EventBus / EventStream (async fan-out)
sandbox.py         Codex-style execution boundary
runtime.py         ConversationRuntime (tool-use loop)
session.py         Workspace + transcript + checkpoints
orchestrator.py    SwarmOrchestrator — runs build + test layers
llm.py             Anthropic + OpenAI clients
agents/            Agent blueprints (system prompts + tool sets)
tools/             read/write/edit/list, shell, grep, xcodebuild, swiftlint, simctl, apple_docs
api.py             FastAPI router /api/coding/swarm/*
```

## Status & next

See `docs/ROADMAP.md` and `docs/QUALITY_CHECKLIST.md`.
