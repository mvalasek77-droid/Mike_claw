import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Pro analytics

/// Breakdown of the player's closed trades, for Mogul's Pro analytics.
/// Pure and testable: built from positions, no services.
struct TradeStats {
    struct Bucket: Identifiable {
        let name: String
        let trades: Int
        let wins: Int
        let profit: Double
        var id: String { name }
        var winRate: Double { trades == 0 ? 0 : Double(wins) / Double(trades) }
    }

    let bySide: [Bucket]
    let byGenre: [Bucket]
    /// Mean return on the premium paid, as a fraction (0.25 = +25%).
    let averageReturn: Double
    let best: Position?
    let worst: Position?
    let tradeCount: Int

    /// Closed trades only; refunded (voided) trades aren't results.
    init(positions: [Position]) {
        let closed = positions.filter { !$0.isOpen && $0.voided != true }
        func profit(_ p: Position) -> Double { (p.settledPayout ?? 0) - p.cost }

        func buckets(_ key: (Position) -> String) -> [Bucket] {
            Dictionary(grouping: closed, by: key)
                .map { name, group in
                    Bucket(name: name, trades: group.count,
                           wins: group.filter { profit($0) > 0 }.count,
                           profit: group.reduce(0) { $0 + profit($1) })
                }
                .sorted { $0.profit > $1.profit }
        }

        bySide = buckets { $0.side == .call ? "Calls" : "Puts" }
        byGenre = buckets { p in
            let g = p.genre?.trimmingCharacters(in: .whitespaces) ?? ""
            return g.isEmpty || g == "—" ? "Other" : g
        }
        let returns = closed.filter { $0.cost > 0 }.map { profit($0) / $0.cost }
        averageReturn = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)
        best = closed.max { profit($0) < profit($1) }
        worst = closed.min { profit($0) < profit($1) }
        tradeCount = closed.count
    }
}

// MARK: - Trade history export

enum TradeHistoryCSV {
    static let header = "opened,movie,side,strike_millions,quantity,entry_premium,cost,status,opening_millions,payout,profit"

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()

    static func make(positions: [Position]) -> String {
        let rows = positions.sorted { $0.openedAt < $1.openedAt }.map { p -> String in
            let status: String
            if p.isOpen { status = "open" }
            else if p.voided == true { status = "refunded" }
            else if p.actualOWMillions != nil { status = "settled" }
            else { status = "closed early" }
            let payout = p.settledPayout.map { String(format: "%.2f", $0) } ?? ""
            let profit = p.settledPayout.map { String(format: "%.2f", $0 - p.cost) } ?? ""
            let opening = p.actualOWMillions.map { String(format: "%.1f", $0) } ?? ""
            return [
                dateFormatter.string(from: p.openedAt),
                field(p.movieTitle ?? p.movieId),
                p.side == .call ? "CALL" : "PUT",
                String(format: "%.0f", p.strikeMillions),
                "\(p.quantity)",
                String(format: "%.2f", p.entryPremium),
                String(format: "%.2f", p.cost),
                status, opening, payout, profit,
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Quotes a field when it holds a comma, quote or newline.
    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Writes the CSV to a temporary file the share sheet can hand off.
    static func file(positions: [Position]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoxCall trades.csv")
        do {
            try make(positions: positions).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - App icons

enum AppIconChoice: String, CaseIterable, Identifiable {
    case classic, emerald, midnight, noir

    var id: String { rawValue }

    /// The alternate icon set's name, nil for the primary icon.
    var iconName: String? {
        switch self {
        case .classic:  return nil
        case .emerald:  return "AppIcon-Emerald"
        case .midnight: return "AppIcon-Midnight"
        case .noir:     return "AppIcon-Noir"
        }
    }

    var title: String { rawValue.capitalized }

    var previewImage: String {
        (iconName ?? "AppIcon-Classic") + "-Preview"
    }

    @MainActor static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .classic
    }

    @MainActor func apply() async {
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != iconName else { return }
        try? await UIApplication.shared.setAlternateIconName(iconName)
    }
}

// MARK: - Views

/// Mogul's Pro analytics, shown in Portfolio.
struct ProAnalyticsSection: View {
    let positions: [Position]

    var body: some View {
        let stats = TradeStats(positions: positions)
        VStack(alignment: .leading, spacing: 12) {
            if stats.tradeCount == 0 {
                Text("Your breakdown appears once your first trade settles or closes.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    tile("Avg return", String(format: "%+.0f%%", stats.averageReturn * 100),
                         stats.averageReturn >= 0 ? .green : .red)
                    Spacer()
                    if let best = stats.best { tile("Best call", signed(best), .green) }
                    Spacer()
                    if let worst = stats.worst { tile("Worst call", signed(worst), .red) }
                }
                breakdown("By side", stats.bySide)
                breakdown("By genre", stats.byGenre)
            }
        }
        .padding(.vertical, 4)
    }

    private func signed(_ p: Position) -> String {
        String(format: "%+.0f RC", (p.settledPayout ?? 0) - p.cost)
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }
    }

    private func breakdown(_ title: String, _ buckets: [TradeStats.Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(buckets) { b in
                HStack {
                    Text(b.name).font(.caption)
                    Spacer()
                    Text("\(b.wins)/\(b.trades) won · \(Int(b.winRate * 100))%")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    Text(String(format: "%+.0f RC", b.profit))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(b.profit >= 0 ? .green : .red)
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The trade history as a shareable CSV file. The file is written only
/// when the share sheet asks for it, not every time the view redraws.
struct TradeHistoryExport: Transferable {
    let positions: [Position]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            guard let url = TradeHistoryCSV.file(positions: export.positions) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return SentTransferredFile(url)
        }
    }
}

/// Share-sheet button for Mogul's trade-history export.
struct ExportHistoryButton: View {
    let positions: [Position]

    var body: some View {
        ShareLink(item: TradeHistoryExport(positions: positions),
                  preview: SharePreview("BoxCall trades.csv")) {
            Label("Export trade history (CSV)", systemImage: "square.and.arrow.up")
        }
    }
}

/// Mogul's alternate app icons, shown in Profile.
struct AppIconPicker: View {
    @State private var selected: AppIconChoice = .classic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App icon").font(.headline)
            HStack(spacing: 12) {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        selected = choice
                        Haptics.selection()
                        Task { await choice.apply() }
                    } label: {
                        VStack(spacing: 4) {
                            Image(choice.previewImage)
                                .resizable()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selected == choice ? Theme.marqueeGold : .clear, lineWidth: 2)
                                )
                            Text(choice.title).font(.caption2)
                                .foregroundStyle(selected == choice ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.title) app icon")
                    .accessibilityAddTraits(selected == choice ? .isSelected : [])
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .onAppear { selected = AppIconChoice.current }
    }
}
