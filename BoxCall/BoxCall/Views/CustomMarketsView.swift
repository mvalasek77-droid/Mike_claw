import SwiftUI

struct CustomMarketsView: View {
    @EnvironmentObject var portfolio: PortfolioService
    @ObservedObject var service = CustomMarketService.shared
    @State private var showProposeSheet = false
    @State private var showPaywall = false

    var body: some View {
        List {
            Section {
                if portfolio.user.membership == .mogul {
                    Button {
                        showProposeSheet = true
                    } label: {
                        Label("Propose a new market", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.orange)
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Propose your own market — Mogul only")
                                    .font(.subheadline.weight(.semibold))
                                Text("Upgrade to Mogul to write custom prop markets. Everyone can trade them.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("All new markets go through review before they trade. Rules must be objective and settle from a specific public source.")
                    .font(.caption)
            }

            Section("Live prop markets") {
                ForEach(service.visibleMarkets) { m in
                    marketRow(m)
                }
            }
        }
        .navigationTitle("Prop Markets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProposeSheet) {
            ProposeMarketSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func marketRow(_ m: CustomMarket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(m.question).font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge(m.status)
            }
            Text("by @\(m.creatorHandle) · \(m.creatorTier.name)")
                .font(.caption2).foregroundStyle(.secondary)
            Text(m.details).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 12) {
                voteBar(yes: m.yesVolume, no: m.noVolume)
                Text("\(m.yesVolume + m.noVolume) contracts")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ s: CustomMarket.Status) -> some View {
        let (label, color): (String, Color) = {
            switch s {
            case .pendingReview: return ("REVIEW", .yellow)
            case .live: return ("LIVE", .green)
            case .resolvedYes: return ("YES", .green)
            case .resolvedNo: return ("NO", .red)
            case .cancelled: return ("VOID", .gray)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
    }

    private func voteBar(yes: Int, no: Int) -> some View {
        let total = max(1, yes + no)
        let yesFrac = Double(yes) / Double(total)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(.green.opacity(0.6))
                    .frame(width: geo.size.width * CGFloat(yesFrac))
                Rectangle().fill(.red.opacity(0.6))
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

// MARK: - Propose sheet

struct ProposeMarketSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question: String = ""
    @State private var details: String = ""
    @State private var resolvesOn: Date = Date().addingTimeInterval(30 * 86400)
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Villeneuve's next opens above $50M", text: $question, axis: .vertical)
                        .lineLimit(2...3)
                }
                Section("Settlement rules") {
                    TextField("Where do we look up the answer? Which source, which day, which threshold? Be specific.",
                              text: $details, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section("Resolves on") {
                    DatePicker("Date", selection: $resolvesOn,
                               in: Date()..., displayedComponents: [.date])
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
                Section {
                    Button {
                        submit()
                    } label: {
                        Text("Submit for review").frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
            .navigationTitle("Propose market")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func submit() {
        do {
            try CustomMarketService.shared.propose(
                question: question, details: details, resolvesOn: resolvesOn)
            dismiss()
        } catch {
            err = error.localizedDescription
        }
    }
}
