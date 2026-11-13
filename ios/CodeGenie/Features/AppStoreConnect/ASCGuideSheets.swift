import SwiftUI

/// The tutorial shown before step one: the shape of the whole trip,
/// what it needs, and how the guide helps — so nobody discovers at
/// step three that they needed a Mac.
struct ASCTutorialView: View {
    let appName: String
    var onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private var pages: [SubmissionTutorial.Page] { SubmissionTutorial.pages(appName: appName) }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Before you start")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Skip the tutorial")
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { pair in
                        ScrollView {
                            page(pair.element)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(pair.offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? LiquidGlass.accent : .white.opacity(0.25))
                                .frame(width: i == index ? 22 : 7, height: 7)
                                .motion(Motion.spring, value: index)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Page \(index + 1) of \(pages.count)")

                    PrimaryButton(
                        title: index == pages.count - 1 ? "Start with step 1" : "Next",
                        systemImage: index == pages.count - 1 ? "arrow.right.circle.fill" : "chevron.right",
                        style: .filled
                    ) {
                        if index == pages.count - 1 {
                            finish()
                        } else {
                            Motion.run(Motion.smooth) { index += 1 }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }

    private func page(_ page: SubmissionTutorial.Page) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: page.symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(LiquidGlass.accent.opacity(0.16)))
                .accessibilityHidden(true)
            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(page.body)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            GlassSurface(tier: .raised, corner: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(LiquidGlass.accent)
                                .padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(point)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

/// Shown the moment the user confirms they submitted: what Apple does
/// now, what to do in the meantime, and what each outcome will mean.
struct ASCAfterSubmissionView: View {
    let appName: String
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "paperplane.circle.fill")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(LiquidGlass.success)
                                .accessibilityHidden(true)
                            Text(AfterSubmission.headline)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            Text("\(appName) is with Apple. You've done your part — the next move is theirs.")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(AfterSubmission.sections) { section in
                            GlassSurface(tier: .raised, corner: 18) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: section.symbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(LiquidGlass.accent)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(LiquidGlass.accent.opacity(0.16)))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(section.title)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText)
                                        Text(section.body)
                                            .font(.system(size: 14, weight: .regular, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                                            .lineSpacing(2)
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        PrimaryButton(title: "Got it — show me the status", systemImage: "checkmark", style: .filled) {
                            onDone()
                            dismiss()
                        }
                        Color.clear.frame(height: 16)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("What happens now")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(false)
    }
}
