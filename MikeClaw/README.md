# MikeClaw — Agentic AI for iPhone

A native iOS app bringing the **Openclaw** agentic experience to iPhone. Built with SwiftUI, Claude API, MCP (Model Context Protocol), and Apple's App Intents framework.

---

## What It Does

MikeClaw is a **Claude-powered agentic assistant** that runs natively on iPhone. It can:

- **Have conversations** with Claude (claude-sonnet-4-6 by default)
- **Use tools** via MCP servers you configure — search the web, query databases, call APIs
- **Run as an agentic loop** — Claude reasons, calls tools, observes results, loops until done
- **Integrate with Siri & Shortcuts** — ask Claude from anywhere in iOS via App Intents
- **Work offline-first** — conversations persist locally; API calls go directly device → Anthropic

---

## Architecture

```
iPhone
├── SwiftUI App (iOS 17+)
│   ├── Chat UI         — terminal-inspired dark UI, streaming responses
│   ├── Agentic Loop    — Claude → tool calls → results → Claude (max 10 turns)
│   ├── MCP Client      — HTTP/SSE transport, tools/list + tools/call
│   └── App Intents     — Siri + Shortcuts integration
│
└── External
    ├── api.anthropic.com   — Claude API (direct, no proxy)
    └── Your MCP Servers    — any HTTP MCP endpoint
```

### Key Design Decisions (App Store Safe)

| Rule | How We Comply |
|------|--------------|
| No remote code execution | All logic is compiled Swift; no eval/JIT |
| No undocumented APIs | Uses only URLSession, AppIntents, SwiftUI, Security |
| API key security | Stored in iOS Keychain, never logged |
| Network calls | Only to `api.anthropic.com` + user-configured MCP endpoints |
| No subprocess spawning | MCP is HTTP-only; no local command execution |

---

## Setup

### Requirements
- Xcode 15+ on macOS
- iOS 17+ device or simulator
- Anthropic API key from [console.anthropic.com](https://console.anthropic.com)

### Build
1. Open `MikeClaw.xcodeproj` in Xcode
2. Set your Team under Signing & Capabilities
3. Build & run on your device (⌘R)
4. In the app, go to **Settings** → enter your Anthropic API key

### Optional: Connect MCP Tools
Go to the **Tools** tab → **Add MCP Server** → enter any HTTP MCP endpoint.

The server must respond to JSON-RPC `tools/list` and `tools/call` methods.

---

## Siri / Shortcuts Integration

Once installed, ask Siri:
> *"Ask MikeClaw what's the weather in Vancouver"*
> *"Hey MikeClaw, summarize my last meeting notes"*

Or open the Shortcuts app and add the **Ask Claude** action from MikeClaw.

---

## Apple's Agentic AI Strategy Alignment

This app is designed around the signals from Apple's upcoming WWDC direction:

| Apple Signal | MikeClaw Implementation |
|---|---|
| Siri as standalone chat | App Intents with phrase-based triggers |
| Ambient intelligence | Background Shortcut execution, no app open required |
| App Intents ecosystem | `AskClaudeIntent`, `QuickAnalysisIntent` |
| MCP standardization | Full MCP client with `tools/list` + `tools/call` |
| Privacy-first AI | API key in Keychain; direct device→API calls |
| Agentic-first development | Multi-turn tool loop (up to 10 iterations) |

---

## File Structure

```
MikeClaw/
├── App/
│   ├── MikeClawApp.swift          — @main entry point
│   └── RootView.swift             — tab navigation
├── Models/
│   ├── Message.swift              — Message, Conversation, ToolUse
│   └── MCPTool.swift              — MCP server config, tool schema, JSON-RPC types
├── Services/
│   ├── ClaudeService.swift        — Anthropic API, streaming SSE, non-streaming
│   ├── MCPService.swift           — MCP HTTP client
│   └── AppState.swift             — global state, persistence, Keychain
└── Features/
    ├── Chat/
    │   ├── ChatViewModel.swift    — agentic loop, streaming handler
    │   ├── ChatView.swift         — terminal-style chat UI
    │   └── ConversationListView.swift
    ├── MCP/
    │   ├── MCPServersView.swift   — server management UI
    │   └── AddMCPServerView.swift — add/edit/test server sheet
    ├── Settings/
    │   └── SettingsView.swift     — API key, model, system prompt
    └── Intents/
        └── AppIntents.swift       — Siri + Shortcuts actions
```

---

## Extending MikeClaw

### Add a new App Intent (for new Siri phrases)
```swift
struct MyCustomIntent: AppIntent {
    static let title: LocalizedStringResource = "My Action"
    @Parameter(title: "Input") var input: String

    func perform() async throws -> some ProvidesDialog {
        // call ClaudeService or MCPService here
        return .result(dialog: "Done!")
    }
}
// Register in MikeClawShortcuts.appShortcuts
```

### Add a built-in tool (without MCP)
Add a `ClaudeTool` definition to `AppState.claudeTools` and handle its name in `ChatViewModel.executeToolCall`.

---

## License
MIT
