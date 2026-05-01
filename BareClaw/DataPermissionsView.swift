import SwiftUI

// MARK: - DataPermissionsView
//
// Shown as the final onboarding step (after companion selection).
// User can opt in or out of each data source individually.
// All are off by default — the user opts IN, not out.
// The companion uses whatever is enabled to build a richer profile.

struct DataPermissionsView: View {
    @ObservedObject var persona: UserPersona
    let onComplete: () -> Void

    private var companionName: String {
        CompanionPersonality.find(id: persona.selectedCompanionID)?.name ?? "Your companion"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BCSizing.spacingLG) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("🔒 Your privacy matters")
                        .font(BCFont.caption())
                        .foregroundColor(.BC.accent)
                    Text("Help \(companionName) know you better")
                        .font(BCFont.title())
                        .foregroundColor(.BC.textPrimary)
                    Text("""
                    The more \(companionName) understands your life, the better they can support you. \
                    All of this is optional — turn on only what you're comfortable with. \
                    You can change these settings anytime.
                    """)
                        .font(BCFont.body())
                        .foregroundColor(.BC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BCSizing.spacingLG)

                // Permission cards
                VStack(spacing: 12) {
                    PermissionCard(
                        icon: "envelope.fill",
                        iconColor: .blue,
                        title: "Email",
                        subtitle: "Lets \(companionName) help draft and talk through email moments you bring into chat.",
                        benefit: "Better support around work, commitments, and important messages you share.",
                        enabled: $persona.trackingPermissions.emailEnabled,
                        onToggle: { syncTrackingPermissions() }
                    )

                    PermissionCard(
                        icon: "message.fill",
                        iconColor: .green,
                        title: "Messages",
                        subtitle: "Lets \(companionName) help with texts, replies, conflicts, and celebrations you describe.",
                        benefit: "Learns who matters to you from what you choose to share.",
                        enabled: $persona.trackingPermissions.messagesEnabled,
                        onToggle: { syncTrackingPermissions() }
                    )

                    PermissionCard(
                        icon: "safari.fill",
                        iconColor: .orange,
                        title: "Browsing",
                        subtitle: "Lets \(companionName) remember articles, products, and topics you mention in chat.",
                        benefit: "Better recommendations based on shared interests.",
                        enabled: $persona.trackingPermissions.browsingEnabled,
                        onToggle: { syncTrackingPermissions() }
                    )

                    PermissionCard(
                        icon: "location.fill",
                        iconColor: .red,
                        title: "Location Context",
                        subtitle: "Lets \(companionName) remember routines you describe — commute, gym, going out.",
                        benefit: "Time-aware suggestions based on routines you share.",
                        enabled: $persona.trackingPermissions.locationEnabled,
                        onToggle: { syncTrackingPermissions() }
                    )

                    PermissionCard(
                        icon: "calendar",
                        iconColor: .purple,
                        title: "Calendar",
                        subtitle: "Lets \(companionName) see upcoming events and check in before and after important moments.",
                        benefit: "Proactive support around meetings, dates, and deadlines.",
                        enabled: $persona.trackingPermissions.calendarEnabled,
                        onToggle: { syncTrackingPermissions() }
                    )
                }
                .padding(.horizontal, BCSizing.spacingLG)

                // Privacy note
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.BC.success)
                        Text("Your data stays on your device")
                            .font(BCFont.headline())
                            .foregroundColor(.BC.textPrimary)
                    }
                    Text("""
                    All processing happens locally. Nothing is sent to external servers without your \
                    explicit knowledge. You can revoke any permission at any time in Settings.
                    """)
                        .font(BCFont.body(13))
                        .foregroundColor(.BC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BCSizing.spacingMD)
                .background(Color.BC.success.opacity(0.08))
                .cornerRadius(BCSizing.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                        .strokeBorder(Color.BC.success.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, BCSizing.spacingLG)

                // Continue button
                Button {
                    BCHaptic.success()
                    persona.save()
                    syncTrackingPermissions()
                    onComplete()
                } label: {
                    HStack {
                        Text("All set — let's go!")
                            .font(BCFont.headline())
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.BC.accent)
                    .foregroundColor(.black)
                    .cornerRadius(BCSizing.radiusLG)
                    .padding(.horizontal, BCSizing.spacingLG)
                }
                .buttonStyle(BCButtonStyle(haptic: .none))
                .accessibilityLabel("All set, continue to app")
                .padding(.bottom, BCSizing.spacingXL)
            }
            .padding(.top, BCSizing.spacingLG)
        }
    }

    private func syncTrackingPermissions() {
        persona.save()
        DiagnosticsLog.info(
            "permissions",
            "Onboarding tracking permissions synced.",
            details: [
                "email": "\(persona.trackingPermissions.emailEnabled)",
                "messages": "\(persona.trackingPermissions.messagesEnabled)",
                "browsing": "\(persona.trackingPermissions.browsingEnabled)",
                "location": "\(persona.trackingPermissions.locationEnabled)",
                "calendar": "\(persona.trackingPermissions.calendarEnabled)"
            ]
        )
        Task {
            await CompanionDataTracker.shared.updatePermissions(persona.trackingPermissions, persona: persona)
        }
    }
}

// MARK: - PermissionCard

private struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let benefit: String
    @Binding var enabled: Bool
    let onToggle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: BCSizing.spacingMD) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BCFont.headline())
                        .foregroundColor(.BC.textPrimary)
                    Text(benefit)
                        .font(BCFont.body(12))
                        .foregroundColor(.BC.textMuted)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(iconColor)
            }
            .padding(BCSizing.spacingMD)

            if enabled {
                Text(subtitle)
                    .font(BCFont.body(13))
                    .foregroundColor(.BC.textSecondary)
                    .padding(.horizontal, BCSizing.spacingMD)
                    .padding(.bottom, BCSizing.spacingMD)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(enabled ? iconColor.opacity(0.05) : Color.BC.surfaceRaised)
        .cornerRadius(BCSizing.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                .strokeBorder(enabled ? iconColor.opacity(0.3) : Color.BC.border, lineWidth: 1)
        )
        .onChange(of: enabled) { _, _ in
            onToggle?()
        }
        .animation(.spring(response: 0.3), value: enabled)
    }
}

// MARK: - TrackingPermissions model (referenced by UserPersona)

struct TrackingPermissions: Codable {
    var emailEnabled:    Bool = false
    var messagesEnabled: Bool = false
    var browsingEnabled: Bool = false
    var locationEnabled: Bool = false
    var calendarEnabled: Bool = false

    var enabledLearningAreas: [String] {
        var enabled: [String] = []
        if emailEnabled    { enabled.append("email topics the user brings into chat") }
        if messagesEnabled { enabled.append("messaging and relationship moments the user describes") }
        if browsingEnabled { enabled.append("articles, products, and topics the user mentions") }
        if locationEnabled { enabled.append("routines and places the user shares") }
        if calendarEnabled { enabled.append("calendar events") }
        return enabled
    }

    var disabledLearningAreas: [String] {
        var disabled: [String] = []
        if !emailEnabled    { disabled.append("email") }
        if !messagesEnabled { disabled.append("messages") }
        if !browsingEnabled { disabled.append("browsing") }
        if !locationEnabled { disabled.append("location routines") }
        if !calendarEnabled { disabled.append("calendar") }
        return disabled
    }

    var learningSignature: String {
        [
            "email:\(emailEnabled ? 1 : 0)",
            "messages:\(messagesEnabled ? 1 : 0)",
            "browsing:\(browsingEnabled ? 1 : 0)",
            "location:\(locationEnabled ? 1 : 0)",
            "calendar:\(calendarEnabled ? 1 : 0)"
        ].joined(separator: "|")
    }

    /// Returns a descriptive line for the LLM system prompt.
    var systemPromptSummary: String {
        let enabled = enabledLearningAreas
        let disabled = disabledLearningAreas

        guard !enabled.isEmpty else {
            return "The user has not opted into companion tracking. Do not proactively infer, store, or use email, messages, browsing, location routines, or calendar as personalization sources unless the user explicitly shares something in the current message."
        }

        var summary = "The user has opted into these personalization areas: \(enabled.joined(separator: ", "))."
        if !disabled.isEmpty {
            summary += " Disabled areas: \(disabled.joined(separator: ", ")). Do not infer, store, or proactively use disabled areas."
        }
        summary += " Calendar is the only directly accessible app data source; all other enabled areas come from what the user chooses to share in chat."
        return summary
    }
}
