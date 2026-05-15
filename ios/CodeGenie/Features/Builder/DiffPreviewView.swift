import SwiftUI

/// Cursor-style diff preview. Each proposed change can be accepted or
/// rejected. The aggregate decision is reported back via `onApply`.
struct DiffPreviewView: View {
    let diffs: [FileDiff]
    var onApply: ([FileDiff]) -> Void

    @State private var states: [UUID: FileDiff.Status] = [:]
    @State private var expanded: UUID?

    private var decided: [FileDiff] {
        diffs.map { d in
            var copy = d
            copy.status = states[d.id] ?? d.status
            return copy
        }
    }
    private var acceptedCount: Int { decided.filter { $0.status == .accepted }.count }
    private var rejectedCount: Int { decided.filter { $0.status == .rejected }.count }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(diffs) { diff in
                            DiffCard(
                                diff: diff,
                                status: states[diff.id] ?? .pending,
                                isExpanded: expanded == diff.id,
                                onToggle: {
                                    Motion.run(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        expanded = expanded == diff.id ? nil : diff.id
                                    }
                                },
                                onAccept: { states[diff.id] = .accepted; Haptics.tap(intensity: 0.6, sharpness: 0.7) },
                                onReject: { states[diff.id] = .rejected; Haptics.tap(intensity: 0.5, sharpness: 0.85) }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
                .scrollIndicators(.hidden)
            }
            VStack {
                Spacer()
                applyBar
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Review changes")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Spacer()
                summaryPills
            }
            Text("\(diffs.count) files proposed by the swarm. Accept the ones you want; CodeGenie applies and re-builds.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var summaryPills: some View {
        HStack(spacing: 6) {
            StatPill(label: "✓", value: "\(acceptedCount)", icon: nil)
            StatPill(label: "✗", value: "\(rejectedCount)", icon: nil)
        }
    }

    private var applyBar: some View {
        GlassSurface(tier: .deep, corner: 26) {
            HStack(spacing: 10) {
                Button {
                    states = Dictionary(uniqueKeysWithValues: diffs.map { ($0.id, .accepted) })
                } label: {
                    Text("Accept all")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.95))
                }
                .buttonStyle(.plain)

                Button {
                    states = Dictionary(uniqueKeysWithValues: diffs.map { ($0.id, .rejected) })
                } label: {
                    Text("Reject all")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.95))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                PrimaryButton(title: "Apply \(acceptedCount)", systemImage: "checkmark.seal.fill", style: .filled) {
                    onApply(decided.filter { $0.status == .accepted })
                }
                .frame(maxWidth: 200)
                .opacity(acceptedCount > 0 ? 1 : 0.4)
                .allowsHitTesting(acceptedCount > 0)
            }
            .padding(10)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}

// MARK: - Card

private struct DiffCard: View {
    let diff: FileDiff
    let status: FileDiff.Status
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        GlassSurface(tier: status == .accepted ? .deep : .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onToggle) {
                    HStack(spacing: 10) {
                        opChip
                        Text(diff.path)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("+\(diff.additions) −\(diff.deletions)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        statusBadge
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().background(.white.opacity(0.1))
                    DiffBodyView(hunks: diff.hunks())
                    HStack(spacing: 8) {
                        actionButton(title: "Reject", icon: "xmark", tint: LiquidGlass.primaryText.opacity(0.8), filled: status == .rejected, action: onReject)
                        actionButton(title: "Accept", icon: "checkmark", tint: LiquidGlass.success, filled: status == .accepted, action: onAccept)
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var opChip: some View {
        Text(diff.operation.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(opTint.opacity(0.25), in: Capsule())
            .foregroundStyle(opTint)
    }

    private var opTint: Color {
        switch diff.operation {
        case .create: LiquidGlass.success
        case .modify: LiquidGlass.accent
        case .delete: .red
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .pending:
            EmptyView()
        case .accepted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LiquidGlass.success)
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    private func actionButton(title: String, icon: String, tint: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(filled ? tint.opacity(0.25) : .white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? tint.opacity(0.5) : .white.opacity(0.12)))
            .foregroundStyle(filled ? tint : LiquidGlass.primaryText.opacity(0.9))
        }
        .buttonStyle(.plain)
    }
}

private struct DiffBodyView: View {
    let hunks: [FileDiff.Hunk]
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(hunks) { hunk in
                HStack(spacing: 0) {
                    Text(prefix(hunk.kind))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint(hunk.kind))
                        .frame(width: 18, alignment: .leading)
                    Text(hunk.content.isEmpty ? " " : hunk.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(textTint(hunk.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(background(hunk.kind))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func prefix(_ k: FileDiff.Hunk.Kind) -> String {
        switch k { case .added: "+"; case .removed: "−"; case .same: " " }
    }
    private func tint(_ k: FileDiff.Hunk.Kind) -> Color {
        switch k { case .added: LiquidGlass.success; case .removed: .red.opacity(0.9); case .same: LiquidGlass.primaryText.opacity(0.4) }
    }
    private func textTint(_ k: FileDiff.Hunk.Kind) -> Color {
        switch k { case .added: LiquidGlass.primaryText; case .removed: LiquidGlass.primaryText.opacity(0.85); case .same: LiquidGlass.primaryText.opacity(0.7) }
    }
    private func background(_ k: FileDiff.Hunk.Kind) -> Color {
        switch k {
        case .added:   LiquidGlass.success.opacity(0.18)
        case .removed: Color.red.opacity(0.18)
        case .same:    .clear
        }
    }
}
