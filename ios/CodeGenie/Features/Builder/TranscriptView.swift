import SwiftUI

/// Renders a SwarmClient's event stream as a readable transcript.
/// Each event becomes one row — agent thoughts, tool calls, tool
/// results, log lines, and errors are styled distinctly.
struct TranscriptView: View {
    @ObservedObject var client: SwarmClient

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(client.events.suffix(200)) { event in
                        TranscriptRow(event: event)
                            .id(event.id)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: client.events.count) { _, _ in
                if let last = client.events.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                Circle()
                    .fill(client.isConnected ? LiquidGlass.success : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(client.isConnected ? "live" : "offline")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(8)
        }
    }
}

private struct TranscriptRow: View {
    let event: SwarmEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                if let agent = event.agent {
                    Text(agent)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(body)
                    .font(.system(size: 12, weight: .regular, design: bodyDesign))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(8)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        switch event.type {
        case "agent.started":  "play.circle.fill"
        case "agent.finished": "checkmark.circle.fill"
        case "agent.thought":  "bubble.left.fill"
        case "tool.call":      "wrench.and.screwdriver.fill"
        case "tool.result":    "checkmark.seal.fill"
        case "diff":           "doc.text.fill"
        case "test.result":    "testtube.2"
        case "review.finding": "exclamationmark.bubble.fill"
        case "error":          "xmark.octagon.fill"
        case "job.state":      "flag.fill"
        case "done":           "flag.checkered"
        default:               "circle.fill"
        }
    }

    private var tint: Color {
        switch event.type {
        case "agent.started":   LiquidGlass.accent
        case "agent.finished":  LiquidGlass.success
        case "agent.thought":   .white.opacity(0.85)
        case "tool.call":       LiquidGlass.warning
        case "tool.result":     LiquidGlass.success
        case "diff":            LiquidGlass.accentSecondary
        case "review.finding":  LiquidGlass.warning
        case "test.result":     LiquidGlass.accentSecondary
        case "error":           .red
        case "job.state":       LiquidGlass.accent
        case "done":            LiquidGlass.success
        default:                .white.opacity(0.6)
        }
    }

    private var bodyDesign: Font.Design {
        switch event.type {
        case "tool.call", "tool.result", "diff": .monospaced
        default: .rounded
        }
    }

    private var body: String {
        switch event.type {
        case "agent.started":   return "started"
        case "agent.finished":
            if let calls = event.payload["tool_calls"] as? Int {
                return "finished — \(calls) tool calls"
            }
            return "finished"
        case "agent.thought":
            return (event.payload["text"] as? String) ?? "(thinking…)"
        case "tool.call":
            let tool = (event.payload["tool"] as? String) ?? "?"
            let args = (event.payload["arguments"] as? [String: Any])?
                .keys.sorted().joined(separator: ", ") ?? ""
            return "→ \(tool)(\(args))"
        case "tool.result":
            let tool = (event.payload["tool"] as? String) ?? "?"
            let ok = (event.payload["ok"] as? Bool) ?? true
            let preview = (event.payload["content_preview"] as? String) ?? ""
            return "← \(tool) \(ok ? "✓" : "✗") \(preview.prefix(120))"
        case "diff":
            let path = (event.payload["path"] as? String) ?? "?"
            let op   = (event.payload["operation"] as? String) ?? "modify"
            return "\(op): \(path)"
        case "review.finding":
            let title = (event.payload["title"] as? String) ?? "finding"
            let sev = (event.payload["severity"] as? String) ?? "info"
            return "[\(sev)] \(title)"
        case "test.result":
            let p = event.payload["passed"] as? Int ?? 0
            let f = event.payload["failed"] as? Int ?? 0
            return "tests: \(p) passed, \(f) failed"
        case "job.state":
            return "state → \((event.payload["state"] as? String) ?? "?")"
        case "done":
            let ok = (event.payload["success"] as? Bool) ?? false
            return ok ? "build complete" : "build aborted"
        case "error":
            return (event.payload["message"] as? String) ?? "error"
        default:
            return event.type
        }
    }
}
