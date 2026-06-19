import SwiftUI

/// Production revision passes. Each new pass takes the next color in the WGA
/// order; starting a pass stamps subsequently-edited pages with that color so a
/// crew shooting from paper can see what changed.
struct RevisionsView: View {
    @Binding var screenplay: Screenplay

    private var currentColor: String? { screenplay.revisions.last?.colorName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(tier: .raised) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURRENT PASS").font(.labelSmall).foregroundStyle(Palette.accent)
                        HStack {
                            Circle()
                                .fill(RevisionPalette.color(for: currentColor ?? "White"))
                                .frame(width: 18, height: 18)
                            Text(screenplay.revisions.last?.name ?? "First Draft")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.primaryText)
                        }
                        Text("Marked elements: \(markedCount)")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                PrimaryButton(title: "Start \(RevisionPalette.next(after: currentColor)) revision",
                              systemImage: "paintbrush.pointed.fill") {
                    startNextRevision()
                }

                if markedCount > 0 {
                    Button(role: .destructive) {
                        for i in screenplay.elements.indices {
                            screenplay.elements[i].revisionColor = nil
                        }
                        Haptics.tap()
                    } label: {
                        Label("Clear all revision marks", systemImage: "eraser")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .foregroundStyle(Palette.danger)
                }

                SectionHeader("History")
                if screenplay.revisions.isEmpty {
                    Text("No revisions yet.").font(.subheadline).foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(screenplay.revisions.reversed()) { revision in
                        HStack {
                            Circle()
                                .fill(RevisionPalette.color(for: revision.colorName))
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(revision.name).foregroundStyle(Palette.primaryText)
                                Text(revision.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            Spacer()
                            if revision.locked {
                                Image(systemName: "lock.fill").foregroundStyle(Palette.secondaryText)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Palette.secondaryText.opacity(0.15))
                    }
                }
            }
            .padding(16)
        }
    }

    private var markedCount: Int {
        screenplay.elements.filter { $0.revisionColor != nil }.count
    }

    private func startNextRevision() {
        let next = RevisionPalette.next(after: currentColor)
        let revision = Revision(name: "\(next) Revision", colorName: next)
        screenplay.revisions.append(revision)
        Haptics.success()
    }
}
