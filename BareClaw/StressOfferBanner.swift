import SwiftUI

// MARK: - StressOfferBanner
//
// Appears from the bottom whenever StressLearningEngine surfaces an offer.
// Design: WhatsApp-notification meets Apple Music mini-player.
//   • Companion avatar chip + name
//   • The warm offer message
//   • Two buttons: Accept (opens the app/action) | Not now
//   • Auto-dismisses after 14 seconds if user ignores it
//   • Swipe down to dismiss early

struct StressOfferBanner: View {

    @ObservedObject private var engine = StressLearningEngine.shared

    @State private var dragY:        CGFloat = 0
    @State private var dismissTask:  Task<Void, Never>? = nil
    @State private var appeared:     Bool = false

    private let companion: CompanionPersonality = {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }()

    var body: some View {
        if let offer = engine.currentOffer {
            banner(offer: offer)
                .offset(y: dragY)
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            if v.translation.height > 0 { dragY = v.translation.height }
                        }
                        .onEnded { v in
                            if v.translation.height > 60 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragY = 0
                                }
                            }
                        }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal:   .move(edge: .bottom).combined(with: .opacity)
                ))
                .onAppear {
                    appeared = true
                    scheduleDismiss()
                }
                .onDisappear { appeared = false }
        }
    }

    // MARK: - Banner card

    private func banner(offer: StressOffer) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 12) {
                // Companion avatar
                ZStack {
                    Circle()
                        .fill(companion.accentColor.opacity(0.25))
                        .frame(width: 44, height: 44)
                    Text(String(companion.name.prefix(1)))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                // Message
                VStack(alignment: .leading, spacing: 5) {
                    Text(companion.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(companion.accentColor)
                    Text(offer.message)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Action buttons
            HStack(spacing: 12) {
                // Accept
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        engine.acceptOffer()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: iconName(for: offer.action.category))
                            .font(.system(size: 13, weight: .semibold))
                        Text(shortLabel(for: offer.action))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(companion.accentColor)
                    )
                }

                // Not now
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        engine.rejectOffer()
                    }
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.10))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    companion.accentColor.opacity(0.18),
                                    Color(hex: "#0D1117").opacity(0.80)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(companion.accentColor.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, y: -4)
        .padding(.horizontal, 12)
    }

    // MARK: - Auto-dismiss

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { dismiss() }
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            engine.rejectOffer()
        }
    }

    // MARK: - Helpers

    private func shortLabel(for action: StressReliefAction) -> String {
        switch action.category {
        case .streaming:  return "Open"
        case .food:       return "Order"
        case .music:      return "Play"
        case .movement:   return "Let's go"
        case .breathing:  return "Start"
        case .social:     return "Call"
        case .custom:     return "Yes"
        }
    }

    private func iconName(for category: StressReliefAction.Category) -> String {
        switch category {
        case .streaming:  return "play.tv.fill"
        case .food:       return "fork.knife"
        case .music:      return "music.note"
        case .movement:   return "figure.walk"
        case .breathing:  return "wind"
        case .social:     return "phone.fill"
        case .custom:     return "checkmark"
        }
    }
}
