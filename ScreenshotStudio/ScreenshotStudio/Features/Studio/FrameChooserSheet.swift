import SwiftUI

/// Identifiable batch of extracted video frames so it can drive `.sheet(item:)`.
struct FrameBatch: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

/// Lets the user pick which extracted App Preview frames to turn into slides.
struct FrameChooserSheet: View {
    let frames: [UIImage]
    var durationWarning: String? = nil
    var onAdd: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let durationWarning {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(LiquidGlass.warning)
                        Text(durationWarning)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    }
                    .padding(12)
                    .background(LiquidGlass.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                if frames.isEmpty {
                    ContentUnavailableView(
                        "No frames",
                        systemImage: "film",
                        description: Text("Couldn't read frames from that video. Try a different clip.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { index, image in
                            frameCell(index, image)
                        }
                    }
                    .padding(20)
                }
            }
            .background(LiquidGlassBackground().ignoresSafeArea())
            .navigationTitle("Choose frames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        let chosen = selected.sorted().map { frames[$0] }
                        onAdd(chosen)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func frameCell(_ index: Int, _ image: UIImage) -> some View {
        let isSelected = selected.contains(index)
        return Button {
            if isSelected { selected.remove(index) } else { selected.insert(index) }
            Haptics.selection()
        } label: {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.15)),
                                      lineWidth: isSelected ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? LiquidGlass.accent : .white.opacity(0.7))
                        .padding(6)
                        .shadow(radius: 2)
                }
        }
        .buttonStyle(.plain)
    }
}
