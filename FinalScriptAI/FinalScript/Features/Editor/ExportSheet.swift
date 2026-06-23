import SwiftUI

/// Export a screenplay to Fountain (free), Final Draft (.fdx), or a laid-out
/// PDF. Pro formats are gated behind the subscription; Fountain is always
/// available so writers are never locked out of their own work.
struct ExportSheet: View {
    let screenplay: Screenplay
    @EnvironmentObject private var entitlements: Entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    private var safeName: String {
        let base = screenplay.title.isEmpty ? "Screenplay" : screenplay.title
        return base.replacingOccurrences(of: "/", with: "-")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    exportRow(title: "Fountain (.fountain)",
                              subtitle: "Plain-text, opens anywhere",
                              symbol: "doc.plaintext",
                              url: fountainURL(),
                              pro: false)
                }
                Section {
                    exportRow(title: "Final Draft (.fdx)",
                              subtitle: "Industry standard XML",
                              symbol: "doc.text",
                              url: fdxURL(),
                              pro: true)
                    exportRow(title: "PDF",
                              subtitle: "Print-ready, US Letter Courier",
                              symbol: "doc.richtext",
                              url: pdfURL(),
                              pro: true)
                } footer: {
                    if !entitlements.isPro {
                        Text("Final Draft and PDF export are Pro features.")
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func exportRow(title: String, subtitle: String, symbol: String,
                           url: URL?, pro: Bool) -> some View {
        if pro && !entitlements.isPro {
            Button { showPaywall = true } label: {
                rowLabel(title: title, subtitle: subtitle, symbol: symbol, locked: true)
            }
        } else if let url {
            ShareLink(item: url) {
                rowLabel(title: title, subtitle: subtitle, symbol: symbol, locked: false)
            }
        } else {
            rowLabel(title: title, subtitle: subtitle, symbol: symbol, locked: false)
                .opacity(0.5)
        }
    }

    private func rowLabel(title: String, subtitle: String, symbol: String, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.primaryText)
                Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Image(systemName: locked ? "lock.fill" : "square.and.arrow.up")
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: - File generation

    private func write(_ data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension(ext)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func fountainURL() -> URL? {
        let text = FountainParser.serialize(screenplay.elements)
        return write(Data(text.utf8), ext: "fountain")
    }

    private func fdxURL() -> URL? {
        let text = FDXExporter.export(screenplay)
        return write(Data(text.utf8), ext: "fdx")
    }

    private func pdfURL() -> URL? {
        write(PDFExporter.makePDF(for: screenplay), ext: "pdf")
    }
}
