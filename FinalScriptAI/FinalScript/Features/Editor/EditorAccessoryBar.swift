import SwiftUI

/// The bar that floats above the keyboard while editing: element-type control,
/// smart-type suggestions, and the new-element / delete actions. This is what
/// turns a list of text fields into a fast screenwriting surface.
struct EditorAccessoryBar: View {
    @Binding var element: ScreenplayElement
    var suggestions: [String]
    var onCycleType: () -> Void
    var onNewElement: () -> Void
    var onDelete: () -> Void
    var onApplySuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                onApplySuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.screenplay(13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Palette.accent.opacity(0.16), in: Capsule())
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(ElementType.allCases) { type in
                        Button {
                            element.type = type
                            Haptics.selection()
                        } label: {
                            Label(type.displayName,
                                  systemImage: element.type == type ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(element.type.displayName)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(Palette.primaryText)
                }

                Button(action: onCycleType) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(Palette.primaryText)

                Spacer()

                if element.isDualDialogue || element.type == .dialogue || element.type == .character {
                    Button {
                        element.isDualDialogue.toggle()
                        Haptics.selection()
                    } label: {
                        Image(systemName: element.isDualDialogue ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                            .font(.subheadline)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(element.isDualDialogue ? Palette.accent : Palette.primaryText)
                    }
                }

                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.subheadline)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(Palette.danger)
                }

                Button(action: onNewElement) {
                    Image(systemName: "return")
                        .font(.subheadline.weight(.bold))
                        .padding(8)
                        .background(Palette.marqueeGradient, in: Circle())
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
    }
}
