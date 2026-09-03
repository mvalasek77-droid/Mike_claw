import SwiftUI

/// The things only the user can confirm, before they submit.
///
/// Deliberately not a wall of ticks. Each item says why Apple cares,
/// because a checklist whose reasons are invisible gets ticked blindly
/// and then everyone is surprised by the rejection. Items CodeGenie
/// has already proven tick themselves and say so, so the user is only
/// ever asked about things that genuinely need a human.
struct SubmissionChecklistView: View {
    let jobID: UUID
    let appName: String
    /// TestFlight needs far less than a public release, and asking for
    /// screenshot attestations before the user has installed their own
    /// app is how a checklist becomes noise.
    let forAppStore: Bool
    let autoSatisfied: Set<String>

    @ObservedObject var store: ASCSubmissionStore
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: String?

    private var checked: Set<String> { store.checkedItems(for: jobID) }

    private var settled: Set<String> { checked.union(autoSatisfied) }

    private var items: [SubmissionChecklist.Item] {
        SubmissionChecklist.items(forAppStore: forAppStore)
    }

    private var doneCount: Int {
        items.filter { settled.contains($0.id) }.count
    }

    private var isComplete: Bool { doneCount == items.count }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        progressCard
                        ForEach(SubmissionChecklist.Group.allCases) { group in
                            let groupItems = SubmissionChecklist.items(in: group, forAppStore: forAppStore)
                            if !groupItems.isEmpty {
                                groupSection(group, items: groupItems)
                            }
                        }
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Before you submit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Progress

    private var progressCard: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isComplete ? "checkmark.seal.fill" : "list.bullet.clipboard.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isComplete ? LiquidGlass.success : LiquidGlass.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isComplete ? "You're ready" : "\(doneCount) of \(items.count) confirmed")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(forAppStore ? "For the public App Store" : "For TestFlight")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule()
                            .fill(isComplete
                                  ? AnyShapeStyle(LiquidGlass.success)
                                  : AnyShapeStyle(LiquidGlass.auroraGradient))
                            .frame(width: proxy.size.width * (Double(doneCount) / Double(max(items.count, 1))))
                            .motion(.spring(response: 0.45), value: doneCount)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)

                Text(isComplete
                     ? "Everything here is confirmed. CodeGenie's own checks run separately when you submit."
                     : "CodeGenie checks what a machine can check. These are the things only you know — and they're where most first apps get rejected.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(doneCount) of \(items.count) confirmed for \(forAppStore ? "the App Store" : "TestFlight")")
    }

    // MARK: Groups

    private func groupSection(_ group: SubmissionChecklist.Group, items: [SubmissionChecklist.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.rawValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(group.blurb)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)

            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: SubmissionChecklist.Item) -> some View {
        let isAuto = autoSatisfied.contains(item.id)
        let isOn = settled.contains(item.id)
        let isExpanded = expanded == item.id

        return GlassSurface(tier: isExpanded ? .deep : .raised, corner: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        guard !isAuto else { return }
                        Haptics.selection()
                        store.setChecklistItem(item.id, checked: !isOn, for: jobID)
                    } label: {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isOn ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuto)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(isOn ? "confirmed" : "not confirmed")
                    .accessibilityHint(isAuto ? "CodeGenie already verified this" : "Double tap to confirm")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(isOn ? 0.65 : 1))
                            .fixedSize(horizontal: false, vertical: true)
                        if isAuto {
                            Label("CodeGenie verified this", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.success)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    Haptics.tap()
                    Motion.run(.spring(response: 0.32)) {
                        expanded = isExpanded ? nil : item.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(isExpanded ? "Hide why" : "Why does Apple care?")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(LiquidGlass.accent)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(item.why)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(14)
        }
    }
}
