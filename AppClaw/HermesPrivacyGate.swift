import Foundation
import SwiftUI

// MARK: - HermesPrivacyGate
//
// Apple guideline 5.1.1 compliance layer.
//
// Rules:
//   • On-device (Apple Foundation Models): no consent needed for the model
//     itself; consent is still shown so users understand what Hermes stores.
//   • Remote (Claude API): explicit consent required BEFORE the first API
//     call.  User must acknowledge data leaves the device.
//
// Consent state is persisted in UserDefaults (not memory) so it survives
// app restarts and is independent of the Hermes memory layer.

// MARK: - Consent state

enum PrivacyConsentState: String {
    case notAsked          // fresh install
    case onDeviceOnly      // user chose on-device only
    case cloudConsented    // user explicitly accepted remote API
    case declined          // user declined all AI features
}

// MARK: - HermesPrivacyGate actor

actor HermesPrivacyGate {
    static let shared = HermesPrivacyGate()

    private let defaultsKey = "com.openclaw.hermes.privacyConsent"

    private(set) var state: PrivacyConsentState = .notAsked

    private init() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let saved = PrivacyConsentState(rawValue: raw) {
            state = saved
        }
    }

    // MARK: - Accessors

    /// True if ANY AI features are enabled.
    var consentGiven: Bool {
        state == .onDeviceOnly || state == .cloudConsented
    }

    /// True only if the user has explicitly accepted remote API calls.
    var cloudConsentGiven: Bool {
        state == .cloudConsented
    }

    /// True if we still need to show the consent screen.
    var needsConsent: Bool {
        state == .notAsked
    }

    // MARK: - Mutations (called from UI)

    func acceptOnDeviceOnly() {
        state = .onDeviceOnly
        persist()
    }

    func acceptCloudAI() {
        state = .cloudConsented
        persist()
    }

    func decline() {
        state = .declined
        persist()
    }

    func reset() {   // for Settings → "Reset AI consent"
        state = .notAsked
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(state.rawValue, forKey: defaultsKey)
    }
}

// MARK: - Privacy consent sheet (SwiftUI)
//
// Present this before any LLM call.  The sheet blocks until the user
// makes a choice — no AI runs without explicit acknowledgement.

struct PrivacyConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onChoice: (PrivacyConsentState) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.OC.background.ignoresSafeArea()
                VStack(spacing: OCSizing.spacingLG) {
                    // Logo + headline
                    VStack(spacing: OCSizing.spacingMD) {
                        BearLogoView(size: 72)
                        Text("OpenClaw AI")
                            .font(OCFont.title())
                            .foregroundColor(.OC.accent)
                        Text("Before we begin, choose how your data is handled.")
                            .font(OCFont.body())
                            .foregroundColor(.OC.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, OCSizing.spacingXL)

                    Divider().background(Color.OC.border)

                    // Options
                    VStack(spacing: OCSizing.spacingMD) {

                        // On-device option (always shown)
                        ConsentOptionCard(
                            icon: "lock.shield.fill",
                            iconColor: .OC.success,
                            title: "On-Device Only",
                            subtitle: "Uses Apple Intelligence (iOS 26+ required). No data leaves your device. Conversations stay private.",
                            badge: "Most Private",
                            badgeColor: .OC.success
                        ) {
                            Task { await HermesPrivacyGate.shared.acceptOnDeviceOnly() }
                            onChoice(.onDeviceOnly)
                            dismiss()
                        }

                        // Cloud option
                        ConsentOptionCard(
                            icon: "cloud.fill",
                            iconColor: .OC.primary,
                            title: "Cloud AI (Claude)",
                            subtitle: "Uses Anthropic's Claude API. Your messages are sent to Anthropic's servers to generate responses. Anthropic's privacy policy applies.",
                            badge: "More Capable",
                            badgeColor: .OC.primary
                        ) {
                            Task { await HermesPrivacyGate.shared.acceptCloudAI() }
                            onChoice(.cloudConsented)
                            dismiss()
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Decline
                    Button("Use app without AI features") {
                        Task { await HermesPrivacyGate.shared.decline() }
                        onChoice(.declined)
                        dismiss()
                    }
                    .font(OCFont.caption())
                    .foregroundColor(.OC.textMuted)
                    .padding(.bottom)

                    // Privacy policy link
                    Link("Privacy Policy", destination: URL(string: "https://openclaw.app/privacy")!)
                        .font(OCFont.caption())
                        .foregroundColor(.OC.textSecondary)
                        .padding(.bottom, OCSizing.spacingLG)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Consent option card

private struct ConsentOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: OCSizing.spacingMD) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(iconColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: OCSizing.spacingXS) {
                    HStack {
                        Text(title)
                            .font(OCFont.headline())
                            .foregroundColor(.OC.textPrimary)
                        Text(badge)
                            .ocBadge(badgeColor)
                    }
                    Text(subtitle)
                        .font(OCFont.body(13))
                        .foregroundColor(.OC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.OC.textMuted)
            }
            .padding(OCSizing.spacingMD)
        }
        .ocCard()
    }
}

// MARK: - Privacy status banner (for Settings screen)

struct PrivacyStatusBanner: View {
    let state: PrivacyConsentState
    let onReset: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OCFont.headline(13))
                    .foregroundColor(.OC.textPrimary)
                Text(subtitle)
                    .font(OCFont.caption())
                    .foregroundColor(.OC.textSecondary)
            }
            Spacer()
            Button("Reset", action: onReset)
                .font(OCFont.caption())
                .foregroundColor(.OC.accent)
        }
        .padding(OCSizing.spacingMD)
        .ocCard()
    }

    private var iconName: String {
        switch state {
        case .notAsked:       return "questionmark.circle"
        case .onDeviceOnly:   return "lock.shield.fill"
        case .cloudConsented: return "cloud.fill"
        case .declined:       return "xmark.circle"
        }
    }

    private var iconColor: Color {
        switch state {
        case .onDeviceOnly:   return .OC.success
        case .cloudConsented: return .OC.primary
        case .declined:       return .OC.danger
        default:              return .OC.textMuted
        }
    }

    private var title: String {
        switch state {
        case .notAsked:       return "AI not configured"
        case .onDeviceOnly:   return "On-device AI active"
        case .cloudConsented: return "Cloud AI active (Claude)"
        case .declined:       return "AI features disabled"
        }
    }

    private var subtitle: String {
        switch state {
        case .notAsked:       return "Tap to configure"
        case .onDeviceOnly:   return "All processing stays on your device"
        case .cloudConsented: return "Messages sent to Anthropic's servers"
        case .declined:       return "No AI features running"
        }
    }
}

// MARK: - App entry point helper
//
// Call this in your @main App struct to gate AI startup:
//
//   .task {
//       await HermesPrivacyGate.shared.configureHermesIfReady()
//   }

extension HermesPrivacyGate {
    /// Configure Hermes based on current consent state.
    /// Safe to call on every app launch — no-ops if already configured.
    ///
    /// IMPORTANT: configure() is called unconditionally so its auto-bootstrap
    /// logic runs. If the user previously entered an API key (e.g. via Settings)
    /// without going through the onboarding consent screen, configure() detects
    /// the key in Keychain and silently grants consent — preventing a state where
    /// the key exists but the provider is stuck at .none.
    func configureHermesIfReady() async {
        // Always run configure — it handles the "key exists, consent not yet set"
        // auto-bootstrap case that would be blocked by a guard on consentGiven.
        await HermesLLMClient.shared.configure()
        // Kairos only starts once we know AI is actually available.
        guard consentGiven else { return }
        await HermesKairos.shared.start()
    }
}
