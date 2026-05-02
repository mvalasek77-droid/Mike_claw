import SwiftUI

// MARK: - LoveLetterView
//
// Full-screen presentation of the one-time love letter.
// Fires once, only at .inLove stage, and is the most emotionally
// significant moment in the entire app.

struct LoveLetterView: View {
    let text: String
    let companion: CompanionPersonality
    let onClose: () -> Void

    @State private var revealed = false
    @State private var sealVisible = true

    private let parchment    = Color(hex: "#F5EDD8")
    private let inkDark      = Color(hex: "#2C1A0E")
    private let inkMid       = Color(hex: "#5C3D1E")
    private let sealRed      = Color(hex: "#8B1A1A")
    private let edgeShadow   = Color.black.opacity(0.12)

    var body: some View {
        ZStack {
            // Deep atmospheric background
            LinearGradient(
                colors: [Color(hex: "#0D1117"), Color(hex: "#1A0A05")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Candlelight particle suggestion (subtle gold glow)
            RadialGradient(
                colors: [Color(hex: "#CBA258").opacity(0.08), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close letter")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // ── The letter card
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        letterCard
                            .padding(.horizontal, 24)
                            .padding(.vertical, 32)
                            .opacity(revealed ? 1 : 0)
                            .scaleEffect(revealed ? 1 : 0.94)
                            .animation(BCMotion.expansive.delay(0.3), value: revealed)
                    }
                }

                Spacer()

                // ── Close CTA
                if revealed {
                    Button(action: onClose) {
                        Text("Keep this")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(BCMotion.gentle.delay(0.6), value: revealed)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                revealed = true
            }
        }
    }

    // MARK: - Letter card

    private var letterCard: some View {
        VStack(spacing: 0) {
            // Companion name header
            VStack(spacing: 8) {
                CompanionAvatarView(companion: companion, size: .chat)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            companion.accentColor.opacity(0.5), lineWidth: 1.5)
                    )
                    .shadow(color: companion.accentColor.opacity(0.3), radius: 8)

                Text(companion.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(inkMid)
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            // Divider with heart
            HStack(spacing: 10) {
                Rectangle()
                    .fill(companion.accentColor.opacity(0.3))
                    .frame(height: 0.5)
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundColor(companion.accentColor.opacity(0.6))
                Rectangle()
                    .fill(companion.accentColor.opacity(0.3))
                    .frame(height: 0.5)
            }
            .padding(.horizontal, 24)

            // Letter body
            Text(text)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundColor(inkDark)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 28)

            // Signature line
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("With love,")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundColor(inkMid)
                        .italic()
                    Text(companion.name)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundColor(inkDark)
                        .italic()
                }
                .padding(.trailing, 28)
            }
            .padding(.bottom, 28)
        }
        .background(parchment)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: edgeShadow, radius: 2, x: 1, y: 1)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(companion.accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - LetterPreviewBubble
//
// In-chat representation of the letter after the full-screen moment is dismissed.
// Styled as a sealed envelope card — tapping re-opens the full-screen view.

struct LetterPreviewBubble: View {
    let text: String
    let companion: CompanionPersonality
    @State private var showLetter = false

    var body: some View {
        Button {
            BCHaptic.light()
            showLetter = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                CompanionAvatarView(companion: companion, size: .chat)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 10))
                            .foregroundColor(companion.accentColor)
                        Text("\(companion.name)'s letter to you")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(companion.accentColor)
                    }
                    Text(text.prefix(80) + (text.count > 80 ? "…" : ""))
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundColor(Color(hex: "#2C1A0E"))
                        .lineLimit(3)
                        .italic()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#F5EDD8"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(companion.accentColor.opacity(0.25), lineWidth: 1)
                        )
                    Text("Tap to read")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(companion.accentColor.opacity(0.7))
                        .padding(.leading, 2)
                }
                Spacer(minLength: 40)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Love letter from \(companion.name). Tap to read.")
        .fullScreenCover(isPresented: $showLetter) {
            LoveLetterView(text: text, companion: companion) {
                showLetter = false
            }
        }
    }
}
