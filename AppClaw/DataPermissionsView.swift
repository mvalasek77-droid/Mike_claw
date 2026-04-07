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
            VStack(alignment: .leading, spacing: OCSizing.spacingLG) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("🔒 Your privacy matters")
                        .font(OCFont.caption())
                        .foregroundColor(.OC.accent)
                    Text("Help \(companionName) know you better")
                        .font(OCFont.title())
                        .foregroundColor(.OC.textPrimary)
                    Text("""
                    The more \(companionName) understands your life, the better they can support you. \
                    All of this is optional — turn on only what you're comfortable with. \
                    You can change these settings anytime.
                    """)
                        .font(OCFont.body())
                        .foregroundColor(.OC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, OCSizing.spacingLG)

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
                .padding(.horizontal, OCSizing.spacingLG)

                // Privacy note
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.OC.success)
                        Text("Your data stays on your device")
                            .font(OCFont.headline())
                            .foregroundColor(.OC.textPrimary)
                    }
                    Text("""
                    All processing happens locally. Nothing is sent to external servers without your \
                    explicit knowledge. You can revoke any permission at any time in Settings.
                    """)
                        .font(OCFont.body(13))
                        .foregroundColor(.OC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(OCSizing.spacingMD)
                .background(Color.OC.success.opacity(0.08))
                .cornerRadius(OCSizing.radiusMD)
                .overlay(
                    RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                        .strokeBorder(Color.OC.success.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, OCSizing.spacingLG)

                // Continue button
                Button(action: {
                    persona.save()
                    onComplete()
                }) {
                    HStack {
                        Text("All set — let's go!")
                            .font(OCFont.headline())
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.OC.accent)
                    .foregroundColor(.black)
                    .cornerRadius(OCSizing.radiusLG)
                    .padding(.horizontal, OCSizing.spacingLG)
                }
                .padding(.bottom, OCSizing.spacingXL)
            }
            .padding(.top, OCSizing.spacingLG)
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
            HStack(alignment: .center, spacing: OCSizing.spacingMD) {
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
                        .font(OCFont.headline())
                        .foregroundColor(.OC.textPrimary)
                    Text(benefit)
                        .font(OCFont.body(12))
                        .foregroundColor(.OC.textMuted)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(iconColor)
            }
            .padding(OCSizing.spacingMD)

            if enabled {
                Text(subtitle)
                    .font(OCFont.body(13))
                    .foregroundColor(.OC.textSecondary)
                    .padding(.horizontal, OCSizing.spacingMD)
                    .padding(.bottom, OCSizing.spacingMD)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(enabled ? iconColor.opacity(0.05) : Color.OC.surfaceRaised)
        .cornerRadius(OCSizing.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                .strokeBorder(enabled ? iconColor.opacity(0.3) : Color.OC.border, lineWidth: 1)
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
