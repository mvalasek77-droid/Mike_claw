import SwiftUI

/// A linear outline: the structural beats followed by the actual scene
/// headings in the script. Gives a bird's-eye view of the story and lets the
/// writer see beats and scenes side by side.
struct OutlineView: View {
    @Binding var screenplay: Screenplay

    private struct ActGroup: Identifiable {
        let id: Int   // act number
        let beats: [Beat]
    }

    private var sceneHeadings: [ScreenplayElement] {
        screenplay.elements.filter { $0.type == .sceneHeading }
    }

    private func sceneNumber(for scene: ScreenplayElement) -> Int {
        (sceneHeadings.firstIndex(where: { $0.id == scene.id }) ?? 0) + 1
    }

    private var beatsByAct: [ActGroup] {
        Dictionary(grouping: screenplay.beats, by: \.act)
            .map { ActGroup(id: $0.key, beats: $0.value.sorted { $0.order < $1.order }) }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !screenplay.logline.isEmpty {
                    GlassCard(tier: .raised) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LOGLINE").font(.labelSmall).foregroundStyle(Palette.accent)
                            Text(screenplay.logline)
                                .font(.titleSerif)
                                .foregroundStyle(Palette.primaryText)
                        }
                    }
                }

                if !screenplay.beats.isEmpty {
                    SectionHeader("Structure")
                    ForEach(beatsByAct) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Act \(group.id)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Palette.secondaryText)
                            ForEach(group.beats) { beat in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle().fill(beat.colorTag.color)
                                        .frame(width: 8, height: 8).padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(beat.title).foregroundStyle(Palette.primaryText)
                                        if !beat.summary.isEmpty {
                                            Text(beat.summary)
                                                .font(.caption)
                                                .foregroundStyle(Palette.secondaryText)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionHeader(title: "Scenes") {
                    Text("\(sceneHeadings.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.secondaryText)
                }
                if sceneHeadings.isEmpty {
                    Text("No scenes yet. Add a scene heading in the editor.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(sceneHeadings) { scene in
                        HStack(spacing: 10) {
                            Text("\(sceneNumber(for: scene))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.secondaryText)
                                .frame(width: 24, alignment: .trailing)
                            Text(scene.formattedText)
                                .font(.screenplay(14))
                                .foregroundStyle(Palette.primaryText)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        Divider().overlay(Palette.secondaryText.opacity(0.15))
                    }
                }
            }
            .padding(16)
        }
    }
}
