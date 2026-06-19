import SwiftUI

/// The beat board: index cards organized into act columns. Cards capture story
/// beats while breaking the story, before (or alongside) writing pages.
struct BeatBoardView: View {
    @Binding var screenplay: Screenplay
    @State private var editingBeat: Beat?
    @State private var showTemplatePicker = false

    private var acts: [Int] {
        let used = Set(screenplay.beats.map(\.act))
        let base = Set(1...3)
        return Array(used.union(base)).sorted()
    }

    private func beats(in act: Int) -> [Beat] {
        screenplay.beats.filter { $0.act == act }.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(acts, id: \.self) { act in
                    actColumn(act)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if screenplay.beats.isEmpty {
                Button {
                    showTemplatePicker = true
                } label: {
                    Label("Start from a template", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(item: $editingBeat) { beat in
            BeatEditorSheet(beat: beat) { updated in
                upsert(updated)
            } onDelete: {
                screenplay.beats.removeAll { $0.id == beat.id }
            }
        }
        .confirmationDialog("Story template", isPresented: $showTemplatePicker, titleVisibility: .visible) {
            ForEach(StructureLibrary.all) { template in
                Button(template.name) { screenplay.beats = template.makeBeats() }
            }
        }
    }

    private func actColumn(_ act: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Act \(romanNumeral(act))")
                    .font(.headline)
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                Text("\(beats(in: act).count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.secondaryText)
            }

            ForEach(beats(in: act)) { beat in
                BeatCard(beat: beat)
                    .onTapGesture { editingBeat = beat }
                    .contextMenu {
                        moveMenu(for: beat)
                        Button(role: .destructive) {
                            screenplay.beats.removeAll { $0.id == beat.id }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }

            Button {
                let order = beats(in: act).count
                editingBeat = Beat(title: "", act: act, order: order)
            } label: {
                Label("Add card", systemImage: "plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(width: 230)
    }

    @ViewBuilder
    private func moveMenu(for beat: Beat) -> some View {
        Menu("Move to act") {
            ForEach(1...max(3, acts.max() ?? 3), id: \.self) { act in
                Button("Act \(romanNumeral(act))") {
                    var updated = beat
                    updated.act = act
                    updated.order = beats(in: act).count
                    upsert(updated)
                }
            }
        }
    }

    private func upsert(_ beat: Beat) {
        if let idx = screenplay.beats.firstIndex(where: { $0.id == beat.id }) {
            screenplay.beats[idx] = beat
        } else {
            screenplay.beats.append(beat)
        }
    }

    private func romanNumeral(_ n: Int) -> String {
        ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"].indices.contains(n - 1)
            ? ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"][n - 1] : "\(n)"
    }
}

struct BeatCard: View {
    let beat: Beat

    var body: some View {
        GlassCard(tier: .flat, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(beat.colorTag.color).frame(width: 10, height: 10)
                    Text(beat.title.isEmpty ? "Untitled beat" : beat.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(2)
                }
                if !beat.summary.isEmpty {
                    Text(beat.summary)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BeatEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var beat: Beat
    var onSave: (Beat) -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Beat") {
                    TextField("Title", text: $beat.title)
                    TextField("Summary", text: $beat.summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Color") {
                    HStack {
                        ForEach(BeatColor.allCases) { color in
                            Circle()
                                .fill(color.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(.white, lineWidth: beat.colorTag == color ? 2 : 0)
                                )
                                .onTapGesture { beat.colorTag = color }
                        }
                    }
                }
            }
            .navigationTitle("Edit Beat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(beat); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
