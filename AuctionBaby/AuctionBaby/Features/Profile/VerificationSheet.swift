import SwiftUI
import UIKit

/// Verify the account. Two paths, picked at runtime:
///   • Signed in (via Sign in with Apple, slice 1) → server-owned flow:
///     `VerificationService.startVerification()` → the current vendor's next
///     step (manual = "we'll review and notify you"; stub = instant pass;
///     future SDKs = launch the SDK). The user leaves the sheet in a
///     "pending" or "done" state, and the local `verified` flag flips
///     automatically once `AuthService.refreshMe()` (or the "you're verified"
///     push from slice 2) reports the new `verifiedAt`.
///   • Demo / local-only (no session) → the original simulated scan runs and
///     immediately awards the blue check locally, so App Review sees the
///     full flow with nothing configured.
struct VerificationSheet: View {
    /// Callback used only by the local/demo path. On the server path the flag
    /// arrives via the auth-refresh loop, not this closure.
    var onVerified: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var verification: VerificationService

    private enum Phase { case idle, scanning, submitting, pending, done, failed }
    @State private var phase: Phase = .idle
    @State private var sweep = false
    @State private var vendorNote: String?

    /// Do we have a real server identity to attach a verification to? If so,
    /// the button goes through the Worker; if not, we fall back to the sim.
    private var useServerPath: Bool { verification.isEnabled }

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 10)

            ZStack {
                Circle().fill(Theme.verify.opacity(0.14)).frame(width: 150, height: 150)
                Image(systemName: iconName)
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(iconTint)
                    .scaleEffect(phase == .done ? 1.1 : 1)
                if phase == .scanning {
                    RoundedRectangle(cornerRadius: 2).fill(
                        LinearGradient(colors: [.clear, Theme.verify, .clear],
                                       startPoint: .leading, endPoint: .trailing))
                        .frame(width: 150, height: 3)
                        .offset(y: sweep ? 60 : -60)
                }
            }
            .frame(height: 160)

            VStack(spacing: 6) {
                Text(title).font(.system(size: 20, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                if let vendorNote {
                    Text(vendorNote)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            actionButton
                .screenPadding()

            Text(footerNote)
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
        .background(AppBackground().opacity(0.5))
    }

    // MARK: - Copy per phase

    private var title: String {
        switch phase {
        case .idle:       return "Verify your identity"
        case .scanning:   return "Hold still…"
        case .submitting: return "Submitting…"
        case .pending:    return "Verification submitted"
        case .done:       return "You're verified!"
        case .failed:     return "That didn't go through"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle:
            return useServerPath
                ? "Match your face to your photos to earn a blue check the whole floor can trust."
                : "Match your face to your photos to earn a blue check the whole floor can trust."
        case .scanning:   return "Checking your liveness and matching your photos."
        case .submitting: return "Sending your submission for review."
        case .pending:    return "We'll review your submission and let you know as soon as it's done. You'll get a notification the moment your blue check goes live."
        case .done:       return "Your blue check is now live across Auction Baby."
        case .failed:     return "Try again in a moment, or reach out to support if this keeps happening."
        }
    }

    private var footerNote: String {
        useServerPath
            ? "Auction Baby never stores your camera roll; verification only touches your existing profile photos."
            : "Demo: no camera is used. Verification is simulated."
    }

    private var iconName: String {
        switch phase {
        case .done: return "checkmark.seal.fill"
        case .pending: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "faceid"
        }
    }
    private var iconTint: Color {
        switch phase {
        case .failed: return Theme.danger
        default: return Theme.verify
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .done, .pending:
            PrimaryButton(title: "Done", systemImage: "checkmark",
                          gradient: Theme.goldGradient) { dismiss() }
        case .failed:
            PrimaryButton(title: "Try again", systemImage: "arrow.clockwise",
                          gradient: Theme.goldGradient) { start() }
        case .submitting:
            PrimaryButton(title: "Submitting…", systemImage: "faceid",
                          gradient: verifyGradient, enabled: false) { }
        case .scanning:
            PrimaryButton(title: "Scanning…", systemImage: "faceid",
                          gradient: verifyGradient, enabled: false) { }
        case .idle:
            PrimaryButton(title: useServerPath ? "Verify me" : "Scan my face",
                          systemImage: "faceid",
                          gradient: verifyGradient) { start() }
        }
    }

    private var verifyGradient: LinearGradient {
        LinearGradient(colors: [Theme.verify, Color(red: 0.18, green: 0.5, blue: 0.85)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private func start() {
        vendorNote = nil
        if useServerPath {
            startServerFlow()
        } else {
            startLocalScan()
        }
    }

    /// Slice-3 path: talk to the Worker, interpret nextStep.
    private func startServerFlow() {
        phase = .submitting
        Task {
            let result = await verification.startVerification()
            switch result {
            case .success(let response):
                switch response.nextStep.kind {
                case "done":
                    Haptics.success()
                    phase = .done
                    // Server truth just moved; pull it into local UI.
                    _ = await auth.refreshMe()
                case "wait":
                    Haptics.tap()
                    phase = .pending
                    if let note = response.nextStep.message { vendorNote = note }
                case "sdk":
                    // Placeholder for slice 3b — Persona/Onfido SDKs land here.
                    // For now, fall through to "pending" so a user isn't stuck.
                    phase = .pending
                    vendorNote = "This vendor's SDK integration is coming soon."
                default:
                    phase = .pending
                }
            case .failure(let message):
                Haptics.warning()
                phase = .failed
                vendorNote = message
            }
        }
    }

    /// Original local/demo path — a scripted scan animation that always passes.
    /// Kept so Demo Mode + the local-only build have full end-to-end flow.
    private func startLocalScan() {
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
