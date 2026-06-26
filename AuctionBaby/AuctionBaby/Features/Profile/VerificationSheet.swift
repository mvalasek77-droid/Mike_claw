import SwiftUI
import UIKit

/// A simulated selfie-match verification. (In production this would be a
/// liveness/selfie check against the profile photos via a vendor SDK.) Runs a
/// short scan animation, then awards the blue check.
struct VerificationSheet: View {
    var onVerified: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case idle, scanning, done }
    @State private var phase: Phase = .idle
    @State private var sweep = false

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 10)

            ZStack {
                Circle().fill(Theme.verify.opacity(0.14)).frame(width: 150, height: 150)
                Image(systemName: phase == .done ? "checkmark.seal.fill" : "faceid")
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(Theme.verify)
                    .scaleEffect(phase == .done ? 1.1 : 1)
                if phase == .scanning {
                    RoundedRectangle(cornerRadius: 2).fill(
                        LinearGradient(colors: [.clear, Theme.verify, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 150, height: 3)
                        .offset(y: sweep ? 60 : -60)
                }
            }
            .frame(height: 160)

            VStack(spacing: 6) {
                Text(title).font(.system(size: 20, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            if phase == .done {
                PrimaryButton(title: "Done", systemImage: "checkmark", gradient: Theme.goldGradient) { dismiss() }
                    .screenPadding()
            } else {
                PrimaryButton(title: phase == .scanning ? "Scanning…" : "Scan my face",
                              systemImage: "faceid",
                              gradient: LinearGradient(colors: [Theme.verify, Color(red: 0.18, green: 0.5, blue: 0.85)],
                                                       startPoint: .leading, endPoint: .trailing),
                              enabled: phase == .idle) {
                    startScan()
                }
                .screenPadding()
            }
            Text("Demo: no camera is used. Verification is simulated.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 10)
        }
        .background(AppBackground().opacity(0.5))
    }

    private var title: String {
        switch phase {
        case .idle: return "Verify your identity"
        case .scanning: return "Hold still…"
        case .done: return "You're verified!"
        }
    }
    private var subtitle: String {
        switch phase {
        case .idle: return "Match your face to your photos to earn a blue check the whole floor can trust."
        case .scanning: return "Checking your liveness and matching your photos."
        case .done: return "Your blue check is now live across Auction Baby."
        }
    }

    private func startScan() {
        phase = .scanning
        if !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { sweep = true }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            Haptics.success()
            Motion.run(Motion.bouncy) { phase = .done }
            onVerified()
        }
    }
}
