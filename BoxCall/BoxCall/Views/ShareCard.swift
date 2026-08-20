import SwiftUI
import UIKit

/// A rendered, shareable card for a call — turns a trade into a
/// snapshot people iMessage / post to X / drop into a group chat.
/// Rendered off-screen via ImageRenderer into a UIImage that
/// UIActivityViewController hands to the share sheet.
struct ShareCard: View {
    let title: String                 // e.g. "Neon Requiem"
    let side: ContractSide
    let strikeMillions: Double
    let quantity: Int
    let entryPremium: Double
    let handle: String
    let tier: Tier
    let outcomeText: String?          // "+320 RC" if settled, else nil
    let poster: String                // fallback emoji

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, sideColor.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 12) {
                header
                Spacer()
                bigCall
                Spacer()
                footer
            }
            .padding(24)
        }
        .frame(width: 400, height: 400)
        .foregroundStyle(.white)
    }

    private var sideColor: Color { side == .call ? .green : .red }

    private var header: some View {
        HStack {
            Text(poster).font(.system(size: 56))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text("BoxCall — opening-weekend options")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
    }

    private var bigCall: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(side.display)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(sideColor)
                Text("$\(Int(strikeMillions))M strike")
                    .font(.title2.weight(.semibold))
            }
            Text("\(quantity) contracts @ \(entryPremium, specifier: "%.2f") RC")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            if let outcomeText {
                Text(outcomeText)
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(sideColor.opacity(0.25)))
                    .foregroundStyle(sideColor)
                    .padding(.top, 4)
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(tier.color).frame(width: 8, height: 8)
                Text("@\(handle)").font(.caption.weight(.bold))
                Text(tier.name).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("BoxCall")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Share coordinator

enum Sharer {
    /// Render a SwiftUI view into a UIImage and present the system share sheet.
    @MainActor
    static func share<V: View>(_ view: V, message: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return }
        let items: [Any] = [message, uiImage]
        let activityVC = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene,
               let root = ws.windows.first(where: \.isKeyWindow)?.rootViewController
                        ?? ws.windows.first?.rootViewController {
                activityVC.popoverPresentationController?.sourceView = root.view
                root.present(activityVC, animated: true)
                return
            }
        }
    }
}
