import SwiftUI

/// Renders one screenplay element as an in-place editable field with the
/// indentation, casing and emphasis appropriate to its type, so the page on
/// screen reads like the printed page.
struct ElementRow: View {
    @Binding var element: ScreenplayElement
    var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let color = element.revisionColor {
                Rectangle()
                    .fill(RevisionPalette.color(for: color))
                    .frame(width: 3)
                    .cornerRadius(2)
            }

            VStack(alignment: .leading, spacing: 1) {
                if isFocused {
                    Text(element.type.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .transition(.opacity)
                }

                TextField(placeholder, text: $element.text, axis: .vertical)
                    .font(.screenplay(15))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(alignment)
                    .textInputAutocapitalization(element.type.isUppercased ? .characters : .sentences)
                    .autocorrectionDisabled(element.type == .character || element.type == .sceneHeading)
                    .tint(Palette.accent)
            }
            .padding(.leading, leadingIndent)
            .padding(.trailing, trailingIndent)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
        .padding(.vertical, verticalPadding)
    }

    private var placeholder: String {
        switch element.type {
        case .sceneHeading: return "INT. LOCATION - DAY"
        case .character: return "CHARACTER"
        case .dialogue: return "What they say…"
        case .parenthetical: return "(beat)"
        case .transition: return "CUT TO:"
        case .action: return "Describe what we see…"
        default: return element.type.displayName
        }
    }

    /// Phone-scaled indentation that echoes the page's column geometry.
    private var leadingIndent: CGFloat {
        switch element.type {
        case .character: return 90
        case .parenthetical: return 70
        case .dialogue: return 50
        case .transition: return 0
        case .centered: return 0
        default: return 0
        }
    }

    private var trailingIndent: CGFloat {
        switch element.type {
        case .dialogue: return 30
        default: return 0
        }
    }

    private var alignment: TextAlignment {
        switch element.type {
        case .transition: return .trailing
        case .centered: return .center
        default: return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch element.type {
        case .transition: return .trailing
        case .centered: return .center
        default: return .leading
        }
    }

    private var verticalPadding: CGFloat {
        switch element.type {
        case .sceneHeading: return 8
        case .action, .transition: return 4
        default: return 1
        }
    }
}
