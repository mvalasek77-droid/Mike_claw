import SwiftUI

/// The founder's moderation queue: in-app reports land on the Worker (KV +
/// operator email) and get resolved here with one of three dispositions.
/// Apple Guideline 1.2 requires serious reports to be actioned within 24h —
/// this screen is that paper trail.
struct AdminModerationView: View {
    @EnvironmentObject private var backend: BackendService

    @State private var showResolved = false
    @State private var reports: [BackendService.Report] = []
    @State private var loading = false
    @State private var lastError: String?
    @State private var resolving: BackendService.Report?
    @State private var resolutionNote = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                Picker("Queue", selection: $showResolved) {
                    Text("Pending").tag(false)
                    Text("Resolved").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: showResolved) { _, _ in Task { await refresh() } }

                if loading {
                    ProgressView().tint(Theme.gold)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if reports.isEmpty {
                    emptyCard
                } else {
                    ForEach(reports) { row($0) }
                }
                if let err = lastError {
                    Text(err).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                Spacer(minLength: 24)
            }
            .screenPadding().padding(.top, 6)
        }
        .background(AppBackground())
        .navigationTitle("Moderation queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(Theme.gold)
                .disabled(loading)
            }
        }
        .task { await refresh() }
        .confirmationDialog(
            "Resolve report on \(resolving?.profile_name ?? "profile")",
            isPresented: .init(get: { resolving != nil },
                               set: { if !$0 { resolving = nil } }),
            titleVisibility: .visible
        ) {
            Button("Removed from the floor", role: .destructive) { resolve("removed") }
            Button("Warned the user") { resolve("warned") }
            Button("Dismissed — no violation") { resolve("dismissed") }
            Button("Cancel", role: .cancel) { resolving = nil }
        } message: {
            Text("The reporter is emailed the outcome if they opted in.")
        }
    }

    private func row(_ r: BackendService.Report) -> some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.profile_name.isEmpty ? "(unknown profile)" : r.profile_name)
                            .font(.system(size: 14, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(r.ts.prefix(19))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    Chip(text: r.status == "resolved" ? r.disposition : r.reason,
                         color: r.status == "resolved" ? Theme.success : Theme.warning)
                }
                if !r.details.isEmpty {
                    Text(r.details).font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft).lineLimit(4)
                }
                if !r.reporter_email.isEmpty {
                    Text("Reporter: \(r.reporter_email)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                }
                if r.status == "resolved", !r.resolution_note.isEmpty {
                    Text("Note: \(r.resolution_note)")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                } else if r.status != "resolved" {
                    Button {
                        resolutionNote = ""
                        resolving = r
                    } label: {
                        Label("Resolve", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.gold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: showResolved ? "archivebox" : "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(showResolved ? Theme.inkSoft : Theme.success)
            Text(showResolved ? "No resolved reports yet." : "Queue is clear.")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            if !showResolved {
                Text("New in-app reports land here and in your inbox.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func refresh() async {
        loading = true
        lastError = nil
        defer { loading = false }
        switch await backend.fetchReports(resolved: showResolved) {
        case .success(let list): reports = list
        case .failure(let message): lastError = message
        }
    }

    private func resolve(_ disposition: String) {
        guard let report = resolving else { return }
        resolving = nil
        Task {
            if let err = await backend.resolveReport(id: report.id,
                                                     disposition: disposition,
                                                     note: resolutionNote) {
                lastError = err
                Haptics.warning()
            } else {
                reports.removeAll { $0.id == report.id }
                Haptics.success()
            }
        }
    }
}
