import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel: DecodeViewModel
    @State private var showingReleaseGateway: Bool
    @FocusState private var inputFocused: Bool

    init(launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        _viewModel = StateObject(wrappedValue: DecodeViewModel(launchArguments: launchArguments))
        _showingReleaseGateway = State(initialValue: launchArguments.contains("--chaddrop-show-release-gateway"))
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    inputPanel
                    controls
                    actionRow
                    resultPanel
                    repliesPanel
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 36)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 28)
            }
        }
        .sheet(isPresented: $showingReleaseGateway) {
            ReleaseGatewayView()
                .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Label("ChadDrop", systemImage: "quote.bubble.fill")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Button {
                    showingReleaseGateway = true
                } label: {
                    Image(systemName: "checklist.checked")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(IconButtonStyle(size: 44))
                .accessibilityLabel("Open release gateway")
            }

            Text("Paste the text. Get the truth in group-chat English.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
    }

    private var inputPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("The Text", systemImage: "text.bubble.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            viewModel.draft = pasted
                            inputFocused = false
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(CompactButtonStyle())
                }
                .foregroundStyle(.white)

                TextEditor(text: $viewModel.draft)
                    .focused($inputFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(AppTheme.hotPink)
                    .frame(minHeight: 132)
                    .padding(12)
                    .background(AppTheme.panel.opacity(0.74), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        if viewModel.draft.isEmpty {
                            Text("Drop the suspicious masterpiece here...")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.44))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("pasteTextInput")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Tone", selection: $viewModel.tone) {
                ForEach(DecodeTone.allCases) { tone in
                    Text(tone.label).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("tonePicker")

            Picker("Context", selection: $viewModel.context) {
                ForEach(DecodeContext.allCases) { context in
                    Text(context.label).tag(context)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("contextPicker")
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    viewModel.decode()
                    inputFocused = false
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isDecoding {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(viewModel.isDecoding ? "Reading..." : "Decode")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isDecoding)
                .accessibilityIdentifier("decodeButton")

                Button {
                    viewModel.clear()
                    inputFocused = false
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Clear")
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
    }

    private var resultPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.result.headline)
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(viewModel.result.energy)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.lime)
                    }
                    Spacer(minLength: 10)
                    ScoreRing(score: viewModel.result.realityScore)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ResultBlock(title: "The translation", icon: "captions.bubble.fill", text: viewModel.result.translation)
                    ResultBlock(title: "The psychology", icon: "brain.head.profile", text: viewModel.result.psychology)
                }

                FlowTags(values: viewModel.result.receipts, icon: "checkmark.seal.fill")

                if !viewModel.result.flags.isEmpty {
                    FlowTags(values: viewModel.result.flags, icon: "exclamationmark.triangle.fill", tint: AppTheme.orange)
                }
            }
        }
        .accessibilityIdentifier("resultPanel")
    }

    private var repliesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested replies")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            ForEach(Array(viewModel.result.suggestedReplies.enumerated()), id: \.offset) { _, reply in
                ReplyRow(reply: reply)
            }
        }
    }

    private var footer: some View {
        Text("Entertainment, not therapy or legal advice. If a message feels threatening, skip the roast and get support.")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.52))
            .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class DecodeViewModel: ObservableObject {
    @Published var draft = ""
    @Published var tone: DecodeTone = .groupChat
    @Published var context: DecodeContext = .dating
    @Published private(set) var result = DecodeResult.placeholder
    @Published private(set) var isDecoding = false
    @Published private(set) var statusMessage: String?

    private let service: DecodeService

    init(service: DecodeService = DecodeService(), launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        self.service = service
        if launchArguments.contains("--chaddrop-demo-result") {
            applyAppStoreDemo()
        }
    }

    func decode() {
        Task {
            await decodeNow()
        }
    }

    func clear() {
        draft = ""
        result = .placeholder
        statusMessage = nil
    }

    private func decodeNow() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            result = .placeholder
            statusMessage = "Paste something first. The app refuses to roast air."
            return
        }

        isDecoding = true
        statusMessage = nil
        let outcome = await service.decode(text: text, tone: tone, context: context)
        result = outcome.result
        statusMessage = outcome.usedFallback
            ? "Offline mode used. Connect an AI proxy for fresher reads."
            : "AI read complete. Standards remain undefeated."
        isDecoding = false
    }

    private func applyAppStoreDemo() {
        draft = "lol yeah we should definitely hang soon. this week is insane but maybe after things calm down?"
        tone = .groupChat
        context = .dating
        result = DecodeResult(
            headline: "He left the calendar in witness protection.",
            translation: "He likes access to you more than he likes making an actual plan. Cute fog machine, zero reservation.",
            psychology: "Vague future language keeps the door open without requiring effort. The useful test is simple: ask for a day, time, and place.",
            receipts: ["No date", "Soft enthusiasm", "Future fog", "Low logistical effort"],
            suggestedReplies: [
                "I like clear plans. What day and time works?",
                "That sounds cute, but vague. Try again with a location.",
                "I am not mad, I am just no longer donating free confusion."
            ],
            realityScore: 38,
            energy: "Vague with a side of breadcrumbs",
            flags: ["No concrete plan", "Keeps access open"]
        )
        statusMessage = "Demo screenshot loaded for App Store capture."
    }
}

private struct ResultBlock: View {
    let title: String
    let icon: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.sky)
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ReplyRow: View {
    let reply: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .foregroundStyle(AppTheme.hotPink)
                .padding(.top, 3)
            Text(reply)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                UIPasteboard.general.string = reply
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(IconButtonStyle(size: 38))
            .accessibilityLabel("Copy reply")
        }
        .padding(14)
        .background(AppTheme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
    }
}

private struct FlowTags: View {
    let values: [String]
    var icon = "tag.fill"
    var tint = AppTheme.lime

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: icon)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(tint.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(0.28)))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 340
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.13), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                Text("truth")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 76, height: 76)
        .accessibilityLabel("Truth score \(score)")
    }

    private var scoreColor: Color {
        switch score {
        case 75...100: return AppTheme.lime
        case 45..<75: return AppTheme.orange
        default: return AppTheme.hotPink
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.12, green: 0.08, blue: 0.14), Color(red: 0.03, green: 0.10, blue: 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            GeometryReader { proxy in
                Canvas { context, size in
                    let circles: [(CGPoint, CGFloat, Color)] = [
                        (CGPoint(x: size.width * 0.16, y: size.height * 0.18), 170, AppTheme.hotPink.opacity(0.18)),
                        (CGPoint(x: size.width * 0.82, y: size.height * 0.12), 150, AppTheme.sky.opacity(0.16)),
                        (CGPoint(x: size.width * 0.78, y: size.height * 0.86), 210, AppTheme.lime.opacity(0.10))
                    ]
                    for circle in circles {
                        let rect = CGRect(x: circle.0.x - circle.1 / 2, y: circle.0.y - circle.1 / 2, width: circle.1, height: circle.1)
                        context.fill(Path(ellipseIn: rect), with: .color(circle.2))
                    }
                }
                .blur(radius: min(proxy.size.width, 500) * 0.05)
            }
        }
    }
}

private struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 14)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(minHeight: 52)
            .padding(.horizontal, 18)
            .background(AppTheme.hotGradient.opacity(configuration.isPressed ? 0.74 : 1), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.11), in: Capsule())
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size > 40 ? 18 : 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }
}

enum AppTheme {
    static let panel = Color(red: 0.09, green: 0.09, blue: 0.13)
    static let hotPink = Color(red: 1.0, green: 0.22, blue: 0.53)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let lime = Color(red: 0.62, green: 0.94, blue: 0.34)
    static let sky = Color(red: 0.35, green: 0.78, blue: 1.0)
    static let hotGradient = LinearGradient(
        colors: [hotPink, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
