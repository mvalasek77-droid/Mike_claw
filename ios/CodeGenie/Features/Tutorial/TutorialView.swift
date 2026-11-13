import SwiftUI

/// The tour: the whole trip from an idea to a live app, one stop per
/// page.
///
/// It follows the same six milestones as the rail on Home, in the same
/// order and with the same names, so what a newcomer is shown here is
/// the map they then find themselves on. Each page answers what
/// happens, what they do, how long it takes and what it needs — the
/// last of which used to surface only when a user ran into it.
///
/// Two modes:
///   * `.onboarding` — first launch; finishing moves into the app.
///   * `.replay`     — opened from Home or Settings; finishing dismisses.
struct TutorialView: View {
    enum Mode: Equatable {
        case onboarding
        case replay
    }

    var mode: Mode = .replay
    var onFinish: () -> Void

    @State private var index: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let stops = Journey.tour
    /// The stops, then one page that gathers what the trip needs.
    private var pageCount: Int { stops.count + 1 }
    private var isLastPage: Bool { index == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            rail
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 10)

            TabView(selection: $index) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { pair in
                    // Scrollable: with larger text, or on a small
                    // iPhone, a page is taller than the screen.
                    ScrollView {
                        stopPage(pair.element, number: pair.offset + 1)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .tag(pair.offset)
                }
                ScrollView {
                    summaryPage
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .tag(stops.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: index) { _, _ in Haptics.selection() }

            Text("\(index + 1) of \(pageCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                .accessibilityLabel("Slide \(index + 1) of \(pageCount)")
                .padding(.top, 6)

            actionRow
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 8)
        }
        .padding(.top, 12)
        .background(LiquidGlassBackground().ignoresSafeArea())
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                CodeGenieLogo(size: 32, animate: !reduceMotion)
                Text("How it works")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            Spacer()
            Button(mode == .onboarding ? "Skip" : "Close") {
                Haptics.selection()
                finish()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(mode == .onboarding ? "Skip onboarding" : "Close tutorial")
        }
        .padding(.horizontal, 24)
    }

    /// The same six milestones as Home, lit up to where the tour is.
    /// Tapping one jumps to it, so the tour doubles as a reference.
    private var rail: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { pair in
                let reached = pair.offset < index || index >= stops.count
                let isCurrent = pair.offset == index
                Button {
                    Motion.run(Motion.smooth) { index = pair.offset }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(isCurrent ? AnyShapeStyle(LiquidGlass.auroraGradient)
                                      : reached ? AnyShapeStyle(LiquidGlass.success)
                                      : AnyShapeStyle(Color.white.opacity(0.14)))
                                .frame(width: 24, height: 24)
                            if reached {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(pair.offset + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isCurrent ? Color.white : LiquidGlass.primaryText.opacity(0.6))
                            }
                        }
                        Text(pair.element.milestone.label)
                            .font(.system(size: 10, weight: isCurrent ? .bold : .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(isCurrent || reached ? 0.9 : 0.45))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(pair.element.milestone.label), stop \(pair.offset + 1) of \(stops.count)")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .motion(Motion.spring, value: index)
    }

    // MARK: Pages

    private func stopPage(_ stop: Journey.TourStop, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSurface(tier: .raised) {
                OnboardingIllustrationView(kind: .init(stop.milestone))
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(14)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Stop \(number) of \(stops.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .accessibilityHidden(true)
                Text(stop.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(stop.body)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            GlassSurface(tier: .flat, corner: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    fact("hand.tap.fill", "You", stop.youDo, tint: LiquidGlass.accent)
                    fact("clock.fill", "Takes", stop.takes, tint: LiquidGlass.accentSecondary)
                    if let needs = stop.needs {
                        fact("shippingbox.fill", "Needs", needs, tint: LiquidGlass.warning)
                    }
                }
                .padding(14)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func fact(_ symbol: String, _ label: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(text)")
    }

    /// The last page: everything the trip needs in one place, so the
    /// costs and the Mac are known before the first build, not after.
    private var summaryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Before you start")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                    .textCase(.uppercase)
                    .tracking(1.5)
                Text("What you'll need")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text("You can build with nothing but this phone and an AI key. The rest only matters once you want the app on a real iPhone.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

            GlassSurface(tier: .raised, corner: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Journey.tourRequirements, id: \.self) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(LiquidGlass.accent)
                                .accessibilityHidden(true)
                            Text(item)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
            }

            GlassSurface(tier: .flat, corner: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("You're never on your own", systemImage: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Home always shows your next step. Every step of getting onto the App Store has the exact clicks, what usually goes wrong, and a coach you can ask.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            if index > 0 {
                PrimaryButton(title: "Back", systemImage: "chevron.left", style: .ghost) {
                    Motion.run(Motion.smooth) { index -= 1 }
                }
                .frame(maxWidth: 130)
                .accessibilityLabel("Previous slide")
            }
            PrimaryButton(
                title: isLastPage ? finishCTA : "Next",
                systemImage: isLastPage ? finishIcon : "chevron.right",
                style: .filled
            ) {
                if isLastPage {
                    finish()
                } else {
                    Motion.run(Motion.smooth) { index += 1 }
                }
            }
            .accessibilityLabel(isLastPage ? finishCTA : "Next slide")
        }
    }

    private var finishCTA: String {
        switch mode {
        case .onboarding: "Start building"
        case .replay:     "Got it"
        }
    }

    private var finishIcon: String {
        switch mode {
        case .onboarding: "wand.and.stars"
        case .replay:     "checkmark"
        }
    }

    private func finish() {
        onFinish()
        if mode == .replay { dismiss() }
    }
}

#Preview { TutorialView { } }
