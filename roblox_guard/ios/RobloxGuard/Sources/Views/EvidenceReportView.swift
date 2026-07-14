import PhotosUI
import SwiftUI

/// Per-child evidence vault + incident report export.
struct EvidenceReportView: View {
    @EnvironmentObject var store: Store
    let child: Child

    @State private var evidence: [EvidenceItem] = []
    @State private var showUploadSheet = false

    var body: some View {
        List {
            Section {
                Link(destination: store.api.reportURL(childId: child.id)) {
                    Label("Open incident report", systemImage: "doc.text")
                }
                ShareLink(item: store.api.reportURL(childId: child.id)) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Incident report")
            } footer: {
                Text("A complete, printable report: what was observed, what it can mean, the alert timeline, and a hash-verified evidence inventory — ready to hand to Roblox, police, or NCMEC.")
            }

            Section {
                Button {
                    showUploadSheet = true
                } label: {
                    Label("Add a screenshot from your child's device", systemImage: "plus.rectangle.on.rectangle")
                }
            } header: {
                Text("Evidence vault")
            } footer: {
                Text("Screenshot chats and profiles on your child's device BEFORE blocking an account — blocking can hide the history. Every item is timestamped and fingerprinted (SHA-256) at capture so investigators can verify nothing was altered.")
            }

            Section {
                if evidence.isEmpty {
                    Text("No evidence captured yet. Watch-level and elevated alerts automatically capture the public profile involved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(evidence) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: icon(for: item.kind))
                                .foregroundStyle(.tint)
                            Text(item.kindLabel)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(item.capturedAt.prefix(10)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !item.note.isEmpty {
                            Text(item.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("SHA-256 \(item.sha256.prefix(16))…")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        if item.kind != "data_snapshot" {
                            Link("View file", destination: store.api.evidenceFileURL(evidenceId: item.id))
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Evidence & Report")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showUploadSheet) {
            EvidenceUploadSheet(child: child) { await load() }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "profile_screenshot": return "camera.viewfinder"
        case "data_snapshot": return "doc.badge.clock"
        default: return "photo"
        }
    }

    private func load() async {
        evidence = (try? await store.api.evidence(childId: child.id)) ?? []
    }
}

/// Upload flow. The legal warning is not skippable: the confirm toggle is the
/// consent gate for storing the image.
struct EvidenceUploadSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let child: Child
    var onDone: () async -> Void

    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var note = ""
    @State private var confirmedLegal = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Never save or upload sexual imagery of a minor — not even as evidence. Possessing or sending it is illegal regardless of intent. If a chat contains such an image, do not screenshot it; describe it to investigators at report.cybertip.org instead.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Toggle(isOn: $confirmedLegal) {
                        Text("This screenshot contains no sexual imagery of a minor.")
                            .font(.subheadline)
                    }
                }

                Section {
                    PhotosPicker(selection: $selection, matching: .screenshots) {
                        Label(imageData == nil ? "Choose screenshot" : "Screenshot selected ✓",
                              systemImage: "photo.on.rectangle")
                    }
                } header: {    Text("Screenshot")}

                Section {
                    TextField("e.g. Chat where the account asks to move to Discord",
                              text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {    Text("What does this show?")}

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Add evidence")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selection) { _, item in
                Task { imageData = try? await item?.loadTransferable(type: Data.self) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await upload() }
                    }
                    .disabled(imageData == nil || !confirmedLegal || isUploading)
                }
            }
        }
    }

    private func upload() async {
        guard let imageData else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            try await store.api.uploadEvidence(
                childId: child.id, imageData: imageData,
                filename: "screenshot.png", note: note)
            await onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
