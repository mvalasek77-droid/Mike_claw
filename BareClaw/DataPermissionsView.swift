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
                        subtitle: "Lets \(companionName) notice important emails — job offers, appointments, news — and bring them up.",
                        benefit: "Context about your work and commitments.",
                        enabled: $persona.trackingPermissions.emailEnabled
                    )

                    PermissionCard(
                        icon: "message.fill",
                        iconColor: .green,
                        title: "Messages",
                        subtitle: "Lets \(companionName) detect relationship moments — celebrations, conflicts, stressful texts — and respond.",
                        benefit: "The app learns who matters to you and how things are going.",
                        enabled: $persona.trackingPermissions.messagesEnabled
                    )

                    PermissionCard(
                        icon: "safari.fill",
                        iconColor: .orange,
                        title: "Browsing",
                        subtitle: "Lets \(companionName) learn what you're interested in — articles, products, topics — to personalise conversations.",
                        benefit: "Better recommendations and more relevant check-ins.",
                        enabled: $persona.trackingPermissions.browsingEnabled
                    )

                    PermissionCard(
                        icon: "location.fill",
                        iconColor: .red,
                        title: "Location Context",
                        subtitle: "Understands your routines — commute, gym, going out — to send timely messages.",
                        benefit: "Time-aware suggestions like Starbucks runs or gym motivation.",
                        enabled: $persona.trackingPermissions.locationEnabled
                    )

                    PermissionCard(
                        icon: "calendar",
                        iconColor: .purple,
                        title: "Calendar",
                        subtitle: "Lets \(companionName) see upcoming events and check in before and after important moments.",
                        benefit: "Proactive support around meetings, dates, and deadlines.",
                        enabled: $persona.trackingPermissions.calendarEnabled
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
                Button(action: {
                    persona.save()
                    onComplete()
                }) {
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
                .padding(.bottom, BCSizing.spacingXL)
            }
            .padding(.top, BCSizing.spacingLG)
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

    /// Returns a descriptive line for the LLM system prompt.
    var systemPromptSummary: String {
        var enabled: [String] = []
        if emailEnabled    { enabled.append("email context") }
        if messagesEnabled { enabled.append("messaging context") }
        if browsingEnabled { enabled.append("browsing interests") }
        if locationEnabled { enabled.append("location routines") }
        if calendarEnabled { enabled.append("calendar events") }
        guard !enabled.isEmpty else { return "" }
        return "The user has shared the following data sources to help you know them better: \(enabled.joined(separator: ", ")). Use this to make conversations feel more personal and timely."
    }
}
