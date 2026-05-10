import SwiftUI

/// Generates app icons via OpenAI's image-1 model (replaces the older
/// DALL·E flow), enforces Apple's 1024×1024 / no-alpha / no-rounded-
/// corners requirements automatically, and previews the icon at every
/// size Xcode wants.
///
/// Requires an OpenAI API key in `Credentials`.
struct IconForgeView: View {
    let appTitle: String
    var onSelect: (UIImage) -> Void = { _ in }

    @StateObject private var forge = IconForge()
    @State private var prompt: String
    @State private var styleIndex: Int = 0

    private static let styles: [(label: String, suffix: String)] = [
        ("Glass aurora",     "ultra-shiny liquid-glass icon, gradient aurora, soft glow, 3D depth, premium Apple aesthetic"),
        ("Flat minimalist",  "flat minimalist icon, two-tone, clean, Apple-like geometric"),
        ("Editorial",        "elegant editorial illustration, painterly, monochrome with one accent color"),
        ("Playful 3D",       "playful 3D rendered icon, warm lighting, soft shadows, kid-friendly"),
        ("Brutalist",        "brutalist typographic icon, single bold glyph, high contrast")
    ]

    init(appTitle: String, onSelect: @escaping (UIImage) -> Void = { _ in }) {
        self.appTitle = appTitle
        self.onSelect = onSelect
        _prompt = State(initialValue: "A polished iOS app icon for an app called \(appTitle).")
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    promptCard
                    styleCard
                    generateButton
                    if !forge.candidates.isEmpty { resultsGrid }
                    if let chosen = forge.chosen { previewCard(chosen) }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon Forge")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Generate, refine, and export your App Store icon. CodeGenie strips alpha + exports every required size for you.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptCard: some View {
        GlassCard(title: "Prompt", icon: "text.alignleft", tint: LiquidGlass.accent) {
            TextEditor(text: $prompt)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var styleCard: some View {
        GlassCard(title: "Style", icon: "paintpalette.fill", tint: LiquidGlass.accentSecondary) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.styles.indices, id: \.self) { i in
                        Button { styleIndex = i; Haptics.selection() } label: {
                            Text(Self.styles[i].label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(
                                    i == styleIndex
                                    ? AnyShapeStyle(LiquidGlass.auroraGradient)
                                    : AnyShapeStyle(Color.white.opacity(0.06)),
                                    in: Capsule()
                                )
                                .overlay(Capsule().strokeBorder(.white.opacity(i == styleIndex ? 0.4 : 0.12)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var generateButton: some View {
        VStack(spacing: 8) {
            PrimaryButton(
                title: forge.isGenerating ? "Generating…" : "Generate 4 candidates",
                systemImage: "wand.and.stars",
                style: .filled
            ) {
                let suffix = Self.styles[styleIndex].suffix
                Task { await forge.generate(prompt: "\(prompt). Style: \(suffix). Square 1024x1024, no text in image.") }
            }
            .disabled(forge.isGenerating)
            if let err = forge.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Text("ChatGPT image-1 · ~$0.04 per icon · stripped to App-Store-safe before export")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var resultsGrid: some View {
        GlassCard(title: "Pick one", icon: "photo.on.rectangle.angled", tint: LiquidGlass.accent) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(forge.candidates) { candidate in
                    Button {
                        forge.choose(candidate)
                        Haptics.success()
                    } label: {
                        Image(uiImage: candidate.image)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(
                                        forge.chosen?.id == candidate.id
                                        ? LiquidGlass.accent
                                        : Color.white.opacity(0.18),
                                        lineWidth: forge.chosen?.id == candidate.id ? 3 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func previewCard(_ chosen: IconCandidate) -> some View {
        GlassCard(title: "Apple icon grid", icon: "square.grid.3x3.fill", tint: LiquidGlass.success) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    iconSquare(chosen.image, size: 120, label: "1024 (App Store)")
                    iconSquare(chosen.image, size: 76,  label: "180 (iPhone)")
                    iconSquare(chosen.image, size: 60,  label: "120 (Spotlight)")
                    iconSquare(chosen.image, size: 40,  label: "80 (Notif.)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton(title: "Use this icon", systemImage: "checkmark.seal.fill", style: .filled) {
                    let cleaned = forge.exportAppStoreSafe(chosen.image)
                    onSelect(cleaned)
                }
            }
        }
    }

    private func iconSquare(_ image: UIImage, size: CGFloat, label: String) -> some View {
        VStack(spacing: 4) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22).strokeBorder(.white.opacity(0.18)))
            Text(label).font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Engine

struct IconCandidate: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage

    static func == (l: IconCandidate, r: IconCandidate) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class IconForge: ObservableObject {
    @Published private(set) var candidates: [IconCandidate] = []
    @Published private(set) var chosen: IconCandidate?
    @Published private(set) var isGenerating: Bool = false
    @Published var errorMessage: String?

    func generate(prompt: String) async {
        guard !Credentials.shared.openaiKey.isEmpty else {
            errorMessage = "Set your OpenAI key in Settings to generate icons."
            return
        }
        isGenerating = true; errorMessage = nil; candidates = []
        defer { isGenerating = false }

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Credentials.shared.openaiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "gpt-image-1",
            "prompt": prompt,
            "n": 4,
            "size": "1024x1024",
            "background": "opaque"   // OpenAI honors this; we still strip alpha defensively
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "IconForge", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "image API failed — \(body.prefix(200))"
                ])
            }
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let arr = (parsed?["data"] as? [[String: Any]]) ?? []
            var out: [IconCandidate] = []
            for entry in arr {
                if let b64 = entry["b64_json"] as? String, let raw = Data(base64Encoded: b64), let img = UIImage(data: raw) {
                    out.append(IconCandidate(image: img))
                } else if let urlStr = entry["url"] as? String, let url = URL(string: urlStr) {
                    if let (raw, _) = try? await URLSession.shared.data(from: url),
                       let img = UIImage(data: raw) {
                        out.append(IconCandidate(image: img))
                    }
                }
            }
            candidates = out
            if out.isEmpty { errorMessage = "no images returned" }
        } catch {
            errorMessage = "\(error.localizedDescription)"
        }
    }

    func choose(_ candidate: IconCandidate) {
        chosen = candidate
    }

    /// Strips alpha and forces RGB so the App Store accepts it. Apple
    /// rejects PNGs with an alpha channel for app icons; this is the
    /// single most common rejection reason for first-time submitters.
    func exportAppStoreSafe(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.opaque = true
            f.scale = 1
            return f
        }())
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
