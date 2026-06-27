import SwiftUI

/// The mod queue: every pending report across Bro-hoods the current user
/// moderates, with approve/remove/ban actions per row.
struct ModQueueView: View {
    @State private var model: ModQueueViewModel

    init(service: ModerationService) {
        _model = State(initialValue: ModQueueViewModel(service: service))
    }

    var body: some View {
        content
            .navigationTitle("Mod Queue")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("Queue is clear", systemImage: "checkmark.shield",
                                   description: Text("No pending reports."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let reports):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.md) {
                    ForEach(reports) { report in
                        ReportRow(
                            report: report,
                            onApprove: { Task { await model.approve(report) } },
                            onRemove: { Task { await model.remove(report) } },
                            onBan: { Task { await model.ban(report) } }
                        )
                    }
                }
                .padding(Tokens.Spacing.lg)
                .animation(Tokens.Motion.gentle, value: reports)
            }
        }
    }
}

private struct ReportRow: View {
    let report: Report
    let onApprove: () -> Void
    let onRemove: () -> Void
    let onBan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack(spacing: Tokens.Spacing.sm) {
                UserAvatar(user: report.reportedUser, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.reportedUser.handle)
                        .font(Tokens.Typography.caption.weight(.semibold))
                    if let community = report.community {
                        Text(community.name)
                            .font(.caption2)
                            .foregroundStyle(Tokens.Color.textSecondary)
                    }
                }
                Spacer()
                Text(report.reason.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, Tokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .liquidGlass(radius: Tokens.Radius.pill)
            }

            Text(report.preview)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.textPrimary)
                .lineLimit(3)

            if let details = report.details {
                Text(details)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }

            HStack(spacing: Tokens.Spacing.md) {
                Button("Approve", action: onApprove)
                    .buttonStyle(.bordered)
                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Ban", action: onBan)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .disabled(report.community == nil)
            }
        }
        .padding(Tokens.Spacing.lg)
        .liquidGlass()
    }
}
