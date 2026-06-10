import SwiftUI

/// SwiftUI sheet presented when a pipeline step fails and the AI steering
/// engine proposes a recovery action. The user can Approve (apply the fix
/// and retry), Modify (edit fix_params before applying), or Reject (halt
/// the pipeline).
struct RecoveryGate: View {

    // MARK: - Inputs

    let step: PipelineStep
    let errorMessage: String
    let proposal: RecoveryProposal
    let jobID: String

    let onApprove: (RecoveryProposal) -> Void
    let onModify: (RecoveryProposal, [String: String]) -> Void
    let onReject: () -> Void

    // MARK: - State

    @State private var editedFixParams: [String: String] = [:]
    @State private var isEditingParams: Bool = false
    @State private var isApproving: Bool = false
    @State private var isRejecting: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Header ──────────────────────────────────────────
                    headerSection

                    // ── Error message ───────────────────────────────────
                    errorSection

                    // ── AI diagnosis ────────────────────────────────────
                    diagnosisSection

                    // ── Proposed fix ────────────────────────────────────
                    fixSection

                    // ── Fix params (editable) ──────────────────────────
                    if !proposal.fixParams.isEmpty {
                        fixParamsSection
                    }

                    // ── Action badges ───────────────────────────────────
                    badgesSection

                    // ── Action buttons ──────────────────────────────────
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background { LiquidGlassBackground().ignoresSafeArea() }
            .navigationTitle("AI Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject", role: .destructive) {
                        Haptics.warning()
                        onReject()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: step.icon)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(step.tint)
                .frame(width: 68, height: 68)
                .background(step.tint.opacity(0.15), in: Circle())
                .overlay(Circle().strokeBorder(step.tint.opacity(0.3), lineWidth: 1.5))

            Text(step.rawValue)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)

            Text("Step failed — AI has a suggestion")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var errorSection: some View {
        GlassSurface(tier: .deep) {
            VStack(alignment: .leading, spacing: 8) {
                Label("What went wrong", systemImage: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.9))

                Text(errorMessage)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private var diagnosisSection: some View {
        GlassSurface(tier: .raised) {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Diagnosis", systemImage: "brain.head.profile.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accentSecondary)

                Text(proposal.diagnosis)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private var fixSection: some View {
        GlassSurface(tier: .raised) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Proposed Fix", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)

                Text(proposal.fixDescription)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if proposal.requiresHumanAction, let humanAction = proposal.humanActionDescription {
                    Label(humanAction, systemImage: "hand.raised.fill")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(14)
        }
    }

    private var fixParamsSection: some View {
        GlassSurface(tier: .flat) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Fix Parameters", systemImage: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35)) {
                            isEditingParams.toggle()
                        }
                        Haptics.selection()
                    } label: {
                        Text(isEditingParams ? "Done" : "Edit")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                    }
                }

                ForEach(Array(editedFixParams.keys.sorted()), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                            .textCase(.uppercase)

                        if isEditingParams {
                            TextField("Value", text: Binding(
                                get: { editedFixParams[key] ?? "" },
                                set: { editedFixParams[key] = $0 }
                            ))
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LiquidGlass.accent.opacity(0.4), lineWidth: 1))
                        } else {
                            Text(editedFixParams[key] ?? "—")
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private var badgesSection: some View {
        HStack(spacing: 10) {
            actionTypeBadge

            if proposal.autoFix {
                autoFixBadge
            }

            if proposal.confidence > 0 {
                confidenceBadge
            }

            Spacer()
        }
    }

    private var actionTypeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: actionIcon)
                .font(.system(size: 11, weight: .semibold))
            Text(proposal.action.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(actionColor.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(actionColor.opacity(0.3), lineWidth: 0.8))
        .foregroundStyle(actionColor)
    }

    private var autoFixBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "wand.and.stars.inverse")
                .font(.system(size: 11, weight: .semibold))
            Text("Auto-fix available")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LiquidGlass.success.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(LiquidGlass.success.opacity(0.3), lineWidth: 0.8))
        .foregroundStyle(LiquidGlass.success)
    }

    private var confidenceBadge: some View {
        let pct = Int(proposal.confidence * 100)
        return HStack(spacing: 5) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 11, weight: .semibold))
            Text("\(pct)% confident")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LiquidGlass.accent.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(LiquidGlass.accent.opacity(0.3), lineWidth: 0.8))
        .foregroundStyle(LiquidGlass.accent)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Approve (green)
            PrimaryButton(
                title: isApproving ? "Applying fix…" : "Approve & Retry",
                systemImage: "checkmark.circle.fill",
                style: .filled
            ) {
                Haptics.success()
                isApproving = true
                onApprove(proposal)
            }
            .disabled(isApproving || isRejecting)

            // Modify (yellow) — only when there are params to edit
            if !proposal.fixParams.isEmpty {
                PrimaryButton(
                    title: isEditingParams ? "Apply Modified Fix" : "Modify Fix Parameters",
                    systemImage: "pencil.circle.fill",
                    style: .glass
                ) {
                    if isEditingParams {
                        // Apply the modified params
                        Haptics.selection()
                        isEditingParams = false
                        onModify(proposal, editedFixParams)
                    } else {
                        withAnimation(.spring(response: 0.35)) {
                            isEditingParams = true
                        }
                        Haptics.selection()
                    }
                }
                .disabled(isApproving || isRejecting)
            }

            // Reject (red)
            Button {
                Haptics.warning()
                isRejecting = true
                onReject()
            } label: {
                Text("Reject — Stop Pipeline")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Color.red.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isApproving || isRejecting)

            if proposal.action == .manualIntervention,
               let urlString = proposal.fixParams["url"],
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Open in Safari")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(LiquidGlass.accent.opacity(0.85), in: Capsule())
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var actionColor: Color {
        switch proposal.action {
        case .retryWithFix:        return LiquidGlass.success
        case .manualIntervention:  return LiquidGlass.warning
        case .skip:                 return LiquidGlass.accent
        case .abort:                return .red
        }
    }

    private var actionIcon: String {
        switch proposal.action {
        case .retryWithFix:        return "arrow.clockwise.circle.fill"
        case .manualIntervention:  return "hand.raised.fill"
        case .skip:                 return "forward.fill"
        case .abort:                return "xmark.octagon.fill"
        }
    }
}

// MARK: - FailureMode Display

extension FailureMode {
    var displayName: String {
        switch self {
        case .ascSignInRequired:           return "ASC Sign-In Required"
        case .provisioningProfileNotFound:  return "Provisioning Profile Not Found"
        case .iconAlphaChannel:             return "Icon Alpha Channel"
        case .keychainAccessRequired:        return "Keychain Access Required"
        case .distributionCertMissing:      return "Distribution Certificate Missing"
        case .buildNumberConflict:           return "Build Number Conflict"
        case .unknown:                       return "Unknown Error"
        }
    }
}

// MARK: - Preview

#Preview("RecoveryGate") {
    RecoveryGate(
        step: .archive,
        errorMessage: "xcodebuild archive failed: no profile matching 'com.example.app' was found",
        proposal: RecoveryProposal(
            id: "preview-1",
            jobID: "job-preview",
            step: "archive",
            failureMode: .provisioningProfileNotFound,
            action: .retryWithFix,
            diagnosis: "Xcode cannot find a provisioning profile for this bundle ID. A new profile needs to be created via the Apple Developer Portal.",
            fixDescription: "Create a new provisioning profile for com.example.app via the ASC API and install it locally, then retry the archive step.",
            fixParams: ["create_profile": "true", "bundle_id": "com.example.app"],
            confidence: 0.85,
            requiresHumanAction: false,
            humanActionDescription: nil,
            autoFix: true
        ),
        jobID: "job-preview",
        onApprove: { _ in },
        onModify: { _, _ in },
        onReject: {}
    )
}