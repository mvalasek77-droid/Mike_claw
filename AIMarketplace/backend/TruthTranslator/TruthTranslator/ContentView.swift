import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel: DecodeViewModel
    @StateObject private var subscriptionStore = SubscriptionStore()
    @State private var showingReleaseGateway: Bool
    @State private var showingPaywall: Bool
    @State private var legalDoc: ChadDropLegalDoc?
    private let releaseGatewayEnabled: Bool
    @AppStorage("chaddropFreeDecodeCount") private var freeDecodeCount = 0
    @FocusState private var inputFocused: Bool

    init(launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        let releaseGatewayEnabled = launchArguments.contains("--chaddrop-show-release-gateway")
        self.releaseGatewayEnabled = releaseGatewayEnabled
        if launchArguments.contains("--chaddrop-reset-free-decodes") {
            UserDefaults.standard.set(0, forKey: "chaddropFreeDecodeCount")
        }
        _viewModel = StateObject(wrappedValue: DecodeViewModel(launchArguments: launchArguments))
        _showingReleaseGateway = State(initialValue: releaseGatewayEnabled)
        _showingPaywall = State(initialValue: launchArguments.contains("--chaddrop-show-paywall"))
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
                    subscriptionStatus
                    actionRow
                    resultPanel
                    repliesPanel
                    footer
                    legalLinks
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
        .fullScreenCover(isPresented: $showingReleaseGateway) {
            ReleaseGatewayView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: subscriptionStore)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $legalDoc) { doc in
            ChadDropLegalSheet(doc: doc)
                .preferredColorScheme(.dark)
        }
        .task {
            await subscriptionStore.refreshPurchasedProducts()
            await subscriptionStore.loadProducts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Label("ChadDrop", systemImage: "magnifyingglass")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Button {
                    showingPaywall = true
                } label: {
                    Image(systemName: subscriptionStore.isSubscribed ? "checkmark.seal.fill" : "crown.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(IconButtonStyle(size: 44))
                .accessibilityLabel("Open subscription options")

                if releaseGatewayEnabled {
                    Button {
                        showingReleaseGateway = true
                    } label: {
                        Image(systemName: "checklist.checked")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(IconButtonStyle(size: 44))
                    .accessibilityLabel("Open release gateway")
                }
            }

            Text("Drop his text. Find out what he's really saying. 💅")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
    }

    private var subscriptionStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: subscriptionStore.isSubscribed ? "checkmark.seal.fill" : "sparkles")
                .foregroundStyle(subscriptionStore.isSubscribed ? AppTheme.lime : AppTheme.blush)

            Text(subscriptionStore.isSubscribed ? "ChadDrop Pro active." : "\(remainingFreeDecodes) free decodes left.")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 8)

            if !subscriptionStore.isSubscribed {
                Button {
                    showingPaywall = true
                } label: {
                    Text("Go Pro")
                }
                .buttonStyle(CompactButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
    }

    private var inputPanel: some View {
        ZStack {
            // Flower decorations around the text input
            VStack {
                HStack {
                    FlowerDecor(size: 28, color: AppTheme.hotPink, rotation: -15)
                    Spacer()
                    FlowerDecor(size: 22, color: AppTheme.rose, rotation: 20)
                }
                Spacer()
                HStack {
                    FlowerDecor(size: 20, color: AppTheme.lavender, rotation: 30)
                    Spacer()
                    FlowerDecor(size: 26, color: AppTheme.blush, rotation: -10)
                }
            }
            .padding(6)

            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("Paste your text messages to find out what he's really saying")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
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
                                Text("Paste what he said...")
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
                    startDecode()
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isDecoding {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(viewModel.isDecoding ? "Reading..." : "Decode Him")
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
                            .foregroundStyle(AppTheme.blush)
                    }
                    Spacer(minLength: 10)
                    ScoreRing(score: viewModel.result.realityScore)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ResultBlock(title: "What he really means", icon: "captions.bubble.fill", text: viewModel.result.translation)
                    if viewModel.result != .placeholder {
                        ResultBlock(title: "The psychology behind it", icon: "brain.head.profile", text: viewModel.result.psychology)
                    }
                }

                if viewModel.result != .placeholder {
                    FlowTags(values: viewModel.result.receipts, icon: "checkmark.seal.fill")

                    if !viewModel.result.flags.isEmpty {
                        FlowTags(values: viewModel.result.flags, icon: "exclamationmark.triangle.fill", tint: AppTheme.lavender)
                    }
                }
            }
        }
        .accessibilityIdentifier("resultPanel")
    }

    private var repliesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to reply")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            ForEach(Array(viewModel.result.suggestedReplies.enumerated()), id: \.offset) { _, reply in
                ReplyRow(reply: reply)
            }
        }
    }

    private var footer: some View {
        Text("For entertainment, not therapy. If a message feels threatening, skip the app and get real support.")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.52))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legalLinks: some View {
        HStack(spacing: 14) {
            Button { legalDoc = .terms } label: {
                Label("Terms of Use", systemImage: "doc.text.fill")
            }
            .accessibilityIdentifier("termsOfUseLink")

            Button { legalDoc = .privacy } label: {
                Label("Privacy Policy", systemImage: "lock.shield.fill")
            }
            .accessibilityIdentifier("privacyPolicyLink")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.78))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private var remainingFreeDecodes: Int {
        max(0, 3 - freeDecodeCount)
    }

    private func startDecode() {
        inputFocused = false

        let hasDraft = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasDraft else {
            viewModel.decode()
            return
        }

        guard subscriptionStore.isSubscribed || remainingFreeDecodes > 0 else {
            showingPaywall = true
            return
        }

        if !subscriptionStore.isSubscribed {
            freeDecodeCount += 1
        }
        viewModel.decode()
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
            translation: "He wants access, not a plan.",
            psychology: "Vague future language keeps the door open without requiring effort. A clear plan is the useful test.",
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
        statusMessage = nil
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
                .foregroundStyle(AppTheme.lavender)
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
    var tint = AppTheme.blush

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
                Text("reality")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 76, height: 76)
        .accessibilityLabel("Truth score \(score)")
    }

    private var scoreColor: Color {
        switch score {
        case 75...100: return AppTheme.blush
        case 45..<75: return AppTheme.peach
        default: return AppTheme.hotPink
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.04, blue: 0.10), Color(red: 0.18, green: 0.06, blue: 0.16), Color(red: 0.08, green: 0.05, blue: 0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            GeometryReader { proxy in
                Canvas { context, size in
                    let circles: [(CGPoint, CGFloat, Color)] = [
                        (CGPoint(x: size.width * 0.16, y: size.height * 0.18), 190, AppTheme.hotPink.opacity(0.22)),
                        (CGPoint(x: size.width * 0.82, y: size.height * 0.12), 170, AppTheme.lavender.opacity(0.18)),
                        (CGPoint(x: size.width * 0.50, y: size.height * 0.86), 220, AppTheme.rose.opacity(0.14))
                    ]
                    for circle in circles {
                        let rect = CGRect(x: circle.0.x - circle.1 / 2, y: circle.0.y - circle.1 / 2, width: circle.1, height: circle.1)
                        context.fill(Path(ellipseIn: rect), with: .color(circle.2))
                    }
                }
                .blur(radius: min(proxy.size.width, 500) * 0.06)
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
    static let panel = Color(red: 0.18, green: 0.06, blue: 0.14)
    static let hotPink = Color(red: 1.0, green: 0.28, blue: 0.56)
    static let rose = Color(red: 0.96, green: 0.40, blue: 0.68)
    static let blush = Color(red: 1.0, green: 0.62, blue: 0.78)
    static let lavender = Color(red: 0.68, green: 0.48, blue: 0.94)
    static let peach = Color(red: 1.0, green: 0.72, blue: 0.58)
    static let lime = Color(red: 0.62, green: 0.94, blue: 0.34)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let hotGradient = LinearGradient(
        colors: [hotPink, rose],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct FlowerDecor: View {
    var size: CGFloat = 24
    var color: Color = .pink
    var rotation: Double = 0

    var body: some View {
        ZStack {
            // Five petals
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.55))
                    .frame(width: size * 0.45, height: size * 0.85)
                    .offset(y: -size * 0.28)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            // Center
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: size * 0.3, height: size * 0.3)
        }
        .rotationEffect(.degrees(rotation))
    }
}
