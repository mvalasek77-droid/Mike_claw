import SwiftUI
import UIKit

/// Everything the guide shows once the app is with Apple.
///
/// One panel serves all three review steps, because what the user
/// needs depends on Apple's status rather than on which step they are
/// nominally on: a rejection calls for the same help whether it arrives
/// an hour or a week after submitting.
///
/// The panel owns no state about the review itself. It renders the
/// saved record and reports intent upwards, so the same status drives
/// this screen, Home, and the step ticks without any of them drifting.
struct ASCReviewPanel: View {
    let record: ASCSubmissionRecord
    /// Whether this phone can ask Apple directly.
    let canAskApple: Bool
    let isChecking: Bool
    let errorText: String?

    var onCheck: () -> Void
    var onReport: (ASCReviewState) -> Void
    var onPickGuideline: (String?) -> Void
    var onResubmitted: () -> Void
    var onUploadNewBuild: () -> Void
    var onOpenAppStoreConnect: () -> Void
    var onCopied: (String) -> Void

    @State private var pastedMessage: String = ""
    @State private var showPasteBox = false
    @FocusState private var pasteFocused: Bool

    private var progress: ASCReviewProgress {
        record.review ?? ASCReviewProgress(state: .waitingForReview)
    }

    private var state: ASCReviewState { progress.state }

    private var tint: Color {
        switch state.tone {
        case .waiting: LiquidGlass.accent
        case .action:  LiquidGlass.warning
        case .problem: LiquidGlass.error
        case .good:    LiquidGlass.success
        }
    }

    private var icon: String {
        switch state.tone {
        case .waiting: "hourglass"
        case .action:  "hand.point.up.left.fill"
        case .problem: "arrow.uturn.backward.circle.fill"
        case .good:    "checkmark.seal.fill"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            statusCard
            if state.needsFix { rejectionCard }
            if progress.history.count > 1 { timelineCard }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(tint.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.appleLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(state.headline)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Apple's status: \(state.appleLabel). \(state.headline)")

                Text(state.meaning)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let wait = state.typicalWait {
                    Label(wait, systemImage: "clock")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                }

                Divider().background(.white.opacity(0.1))

                Text("What to do")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(1)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(state.nextActions.enumerated()), id: \.offset) { pair in
                        numberedLine(pair.offset + 1, pair.element)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Couldn't check with Apple. \(errorText)")
                }

                checkControls

                Text(lastCheckedLine)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
    }

    private var checkControls: some View {
        VStack(spacing: 10) {
            if canAskApple {
                PrimaryButton(
                    title: isChecking ? "Checking…" : "Check with Apple",
                    systemImage: "arrow.clockwise",
                    style: .filled
                ) { onCheck() }
                .disabled(isChecking)
                .accessibilityHint("Asks App Store Connect for the current review status")
            }

            if state == .pendingDeveloperRelease || state.needsFix || state == .notSubmitted {
                PrimaryButton(
                    title: "Open App Store Connect",
                    systemImage: "safari",
                    style: canAskApple ? .glass : .filled
                ) { onOpenAppStoreConnect() }
            }

            Menu {
                ForEach(ASCReviewState.reportable, id: \.self) { option in
                    Button {
                        Haptics.selection()
                        onReport(option)
                    } label: {
                        if option == state {
                            Label(option.appleLabel, systemImage: "checkmark")
                        } else {
                            Text(option.appleLabel)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .bold))
                    Text(canAskApple ? "Set the status myself" : "Tell CodeGenie what App Store Connect shows")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.5)
                }
                .foregroundStyle(LiquidGlass.accent)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(LiquidGlass.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LiquidGlass.accent.opacity(0.28)))
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Set the review status yourself")
            .accessibilityHint("Pick the status shown on your app's page in App Store Connect")

            if !canAskApple {
                Text("Add an App Store Connect API key in Settings and CodeGenie can check this for you.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var lastCheckedLine: String {
        var parts: [String] = []
        if let version = progress.versionString, !version.isEmpty {
            parts.append("Version \(version)")
        }
        if let checked = progress.lastCheckedAt {
            parts.append("checked \(checked.formatted(.relative(presentation: .named)))")
        } else if let since = progress.stateSince {
            parts.append("since \(since.formatted(date: .abbreviated, time: .shortened))")
        }
        if progress.resubmissions > 0 {
            parts.append("resubmitted \(progress.resubmissions)×")
        }
        return parts.joined(separator: " · ")
    }

    private func numberedLine(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index). \(text)")
    }

    // MARK: Rejection help

    private var selectedGuide: ASCRejectionGuide? {
        progress.rejectionGuideline.flatMap { ASCRejectionGuide.guide(for: $0) }
    }

    private var rejectionCard: some View {
        GlassSurface(tier: .raised, corner: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Work out what Apple wants")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .accessibilityAddTraits(.isHeader)

                if state == .invalidBinary {
                    Text("This one never reached a reviewer, so there is no guideline to look up. The email names an error code; fix that in the app and upload again.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Apple's message names a guideline number. Paste the message and CodeGenie finds it, or pick the number yourself.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    pasteControls
                    guidelinePicker

                    if let guide = selectedGuide {
                        guideDetail(guide)
                    } else if let raw = progress.rejectionGuideline {
                        Text("CodeGenie has no specific notes for guideline \(raw). Read Apple's message closely — it describes exactly what the reviewer saw — and use the coach button at the top to talk it through.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().background(.white.opacity(0.1))

                if needsBuild {
                    PrimaryButton(title: "Go to upload a new build", systemImage: "icloud.and.arrow.up.fill", style: .glass) {
                        onUploadNewBuild()
                    }
                    .accessibilityHint("Jumps back to the upload step. Your other progress is kept.")
                }
                PrimaryButton(title: "I fixed it and resubmitted", systemImage: "paperplane.fill", style: .filled) {
                    onResubmitted()
                }
                .accessibilityHint("Marks the app as waiting for review again")
            }
            .padding(18)
        }
    }

    private var needsBuild: Bool {
        if state == .invalidBinary { return true }
        if state == .metadataRejected { return false }
        return selectedGuide.map { $0.needsNewBuild != .no } ?? false
    }

    private var pasteControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                Motion.run(.spring(response: 0.3)) { showPasteBox.toggle() }
                if showPasteBox { pasteFocused = true }
            } label: {
                Label(showPasteBox ? "Hide the message box" : "Paste Apple's message", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showPasteBox {
                TextEditor(text: $pastedMessage)
                    .focused($pasteFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
                    .accessibilityLabel("Apple's rejection message")
                    .onChange(of: pastedMessage) { _, text in
                        // One guideline found: select it. Several: leave
                        // the choice to the user, who can see them below.
                        let found = ASCRejectionGuide.guidelines(mentionedIn: text)
                        if found.count == 1, found[0] != progress.rejectionGuideline {
                            onPickGuideline(found[0])
                        }
                    }
                Text("The message stays on this phone. It is only read to find the guideline number.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Guidelines found in the pasted text first, then the rest of the
    /// table, so the likely answer is the first thing offered.
    private var guidelineOptions: [String] {
        let found = ASCRejectionGuide.guidelines(mentionedIn: pastedMessage)
        let known = ASCRejectionGuide.all.map(\.id)
        var out = found
        for id in known where !out.contains(id) { out.append(id) }
        return out
    }

    private var guidelinePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(guidelineOptions, id: \.self) { id in
                    let selected = progress.rejectionGuideline == id
                    Button {
                        Haptics.selection()
                        onPickGuideline(selected ? nil : id)
                    } label: {
                        Text(id)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected ? Color.white : LiquidGlass.primaryText.opacity(0.85))
                            .background(
                                selected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.08)),
                                in: Capsule()
                            )
                            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0 : 0.16)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Guideline \(id)\(ASCRejectionGuide.guide(for: id).map { ", \($0.title)" } ?? "")")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func guideDetail(_ guide: ASCRejectionGuide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(guide.id) · \(guide.title)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(guide.needsNewBuild.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(guide.needsNewBuild == .no ? LiquidGlass.success : LiquidGlass.warning)
                .background((guide.needsNewBuild == .no ? LiquidGlass.success : LiquidGlass.warning).opacity(0.16), in: Capsule())

            labelled("What it means", guide.meaning)
            labelled("Usually caused by", guide.usualCause)

            Text("How to fix it")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.8)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(guide.fixes.enumerated()), id: \.offset) { pair in
                    numberedLine(pair.offset + 1, pair.element)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("A reply you can adapt")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(guide.replyTemplate)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = guide.replyTemplate
                    Haptics.success()
                    onCopied("Reply copied. Replace the parts in brackets before you send it.")
                } label: {
                    Label("Copy reply", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copies the reply template to the clipboard")
            }
            .padding(12)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func labelled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.8)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Timeline

    private var timelineCard: some View {
        GlassSurface(tier: .flat, corner: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("So far")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(1)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(progress.history.enumerated()), id: \.offset) { pair in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(pair.offset == progress.history.count - 1 ? tint : LiquidGlass.primaryText.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(pair.element.state.appleLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        Spacer(minLength: 8)
                        Text(pair.element.at.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Reviewer notes

/// Step 13's working surface: a draft of what the reviewer will read,
/// with the blanks only the user can fill called out before Apple
/// finds them.
struct ASCReviewNotesCard: View {
    @Binding var metadata: AppStoreMetadata
    let appName: String
    let summary: String
    let features: [String]
    var onCopied: (String) -> Void

    private var notes: Binding<String> {
        Binding(
            get: { metadata.reviewNotes ?? "" },
            set: { metadata.reviewNotes = $0 }
        )
    }

    private var requiresLogin: Binding<Bool> {
        Binding(
            get: { metadata.requiresLogin ?? false },
            set: { metadata.requiresLogin = $0 }
        )
    }

    private var blanks: [String] {
        ASCCoach.unfilledPlaceholders(in: metadata.reviewNotes ?? "")
    }

    var body: some View {
        GlassCard(title: "Notes for the reviewer", icon: "text.bubble.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: requiresLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My app has a sign-in")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("The reviewer will need a test account that works.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                }
                .tint(LiquidGlass.accent)

                TextEditor(text: notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
                    .accessibilityLabel("Notes for the reviewer")

                if blanks.isEmpty {
                    Label("No blanks left to fill.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(blanks.count) blank\(blanks.count == 1 ? "" : "s") still to fill in:", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.warning)
                        Text(blanks.prefix(5).map { "[\($0)]" }.joined(separator: "  "))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                PrimaryButton(title: "Draft my review notes", systemImage: "wand.and.stars", style: .glass) {
                    metadata.reviewNotes = ASCCoach.reviewNotesDraft(
                        appName: appName,
                        summary: summary,
                        features: features,
                        requiresLogin: metadata.requiresLogin ?? false
                    )
                    Haptics.success()
                }
                .accessibilityHint("Replaces the notes with a fresh draft based on your app")

                PrimaryButton(title: "Copy notes", systemImage: "doc.on.doc", style: .filled) {
                    UIPasteboard.general.string = metadata.reviewNotes ?? ""
                    Haptics.success()
                    onCopied(blanks.isEmpty
                             ? "Notes copied. Paste them into App Review Information."
                             : "Notes copied — but fill in the bracketed blanks before you paste.")
                }
            }
        }
    }
}
