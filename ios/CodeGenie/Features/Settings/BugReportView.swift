import SwiftUI
import UIKit

struct BugReportView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var details = ""
    @State private var includeDiagnostics = true
    @State private var status: String?
    @State private var submitting: Bool = false
    private let client = SwarmClient()

    private let address = "mvalasek77@gmail.com"

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        reportCard
                        diagnosticsCard
                        sendButton
                        if let status {
                            Text(status)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Report a bug", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Tell us what broke, what you tapped, and what you expected. You can submit privately to us, or open a pre-filled email to \(address) — whichever you prefer.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reportCard: some View {
        GlassCard(title: "What happened?", icon: "text.bubble.fill", tint: LiquidGlass.accent) {
            TextEditor(text: $details)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 170)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .overlay(alignment: .topLeading) {
                    if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Example: Try a sample opened, then stayed on Planning architecture forever.")
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.42))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Bug report details")
        }
    }

    private var diagnosticsCard: some View {
        GlassCard(title: "Diagnostics", icon: "stethoscope", tint: LiquidGlass.accentSecondary) {
            Toggle(isOn: $includeDiagnostics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include app state")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Adds version, billing mode, backend URL, and device system info. No API keys.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(LiquidGlass.accent)
        }
    }

    private var sendButton: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: submitting ? "Submitting…" : "Submit privately",
                systemImage: "paperplane.fill",
                style: .filled
            ) {
                Task { await submitPrivately() }
            }
            .disabled(submitting || details.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
            .opacity(details.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 ? 0.5 : 1)
            .accessibilityHint("POSTs the report to the CodeGenie backend — no email client needed.")

            PrimaryButton(title: "Or email it instead", systemImage: "envelope.fill", style: .glass) {
                guard let url = mailURL else {
                    status = "Could not create the email link. Send manually to \(address)."
                    Haptics.error()
                    return
                }
                openURL(url) { accepted in
                    status = accepted ? "Opening Mail..." : "Mail is not configured. Send manually to \(address)."
                }
            }
            .accessibilityHint("Opens Mail with a pre-filled bug report.")
        }
    }

    /// Posts the bug report to the backend. Falls back gracefully to
    /// the email path with a clear error if the POST fails — the user
    /// should never lose their words because the network blipped.
    private func submitPrivately() async {
        submitting = true
        defer { submitting = false }
        let report = BugReport(
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            diagnostics: includeDiagnostics ? diagnostics : nil,
            clientVersion: "0.1.0",
            clientBuild: "1",
            device: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion
        )
        do {
            let id = try await client.submitBugReport(report)
            status = "Sent — reference \(id). Thank you."
            Haptics.success()
            details = ""
        } catch {
            status = "Could not send: \(error.localizedDescription). Try the email path."
            Haptics.error()
        }
    }

    private var mailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "CodeGenie bug report"),
            URLQueryItem(name: "body", value: emailBody),
        ]
        return components.url
    }

    private var emailBody: String {
        var body = """
        What happened:
        \(details.trimmingCharacters(in: .whitespacesAndNewlines))

        Steps to reproduce:
        1.
        2.
        3.

        Expected:

        Actual:
        """
        if includeDiagnostics {
            body += """


            Diagnostics:
            \(diagnostics)
            """
        }
        return body
    }

    private var diagnostics: String {
        let creds = Credentials.shared
        let billing = BillingStore.shared
        return """
        App: CodeGenie 0.1.0 (1)
        iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Auth mode: \(creds.authMode.rawValue)
        Billing plan: \(billing.activePlan.rawValue)
        Hosted status: \(billing.hostedStatusText)
        Backend URL: \(creds.backendURL)
        Has backend token: \(!creds.backendToken.isEmpty)
        Preferred model: \(creds.preferredModelID)
        """
    }
}
