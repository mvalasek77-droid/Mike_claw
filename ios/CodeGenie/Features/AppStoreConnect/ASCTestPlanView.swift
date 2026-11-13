import SwiftUI

/// The test plan, worked through one test at a time.
///
/// Each test opens to show exactly what to do and what should happen,
/// and closes with a verdict. A failure asks for one line about what
/// went wrong, because that line is what the next build is told.
struct ASCTestPlanCard: View {
    let appName: String
    let plan: [TestCase]
    let results: [String: TestResult]
    var onResult: (_ testID: String, _ result: TestResult?) -> Void

    @State private var open: String?
    @State private var notes: [String: String] = [:]
    @FocusState private var noteFocused: String?

    private var summary: TestPlan.Summary { TestPlan.summary(of: plan, results: results) }

    var body: some View {
        VStack(spacing: 14) {
            header
            ForEach(TestCase.Area.allCases) { area in
                let tests = plan.filter { $0.area == area }
                if !tests.isEmpty {
                    areaSection(area, tests)
                }
            }
        }
        .onAppear {
            if open == nil { open = TestPlan.next(in: plan, results: results)?.id }
        }
    }

    // MARK: Header

    private var tint: Color {
        if summary.failed > 0 { return LiquidGlass.error }
        return summary.isPassing ? LiquidGlass.success : LiquidGlass.accent
    }

    private var header: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: summary.failed > 0 ? "exclamationmark.triangle.fill"
                          : summary.isPassing ? "checkmark.shield.fill" : "checklist")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.headline)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("\(summary.done) of \(summary.total) tried")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(tint)
                            .frame(width: proxy.size.width * (Double(summary.done) / Double(max(summary.total, 1))))
                            .motion(.spring(response: 0.45), value: summary.done)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text(guidance)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Test plan. \(summary.headline). \(summary.done) of \(summary.total) tried.")
    }

    private var guidance: String {
        if summary.failed > 0 {
            return "Good — that's what testing is for. Finish the rest, then rebuild with everything you found fixed in one go."
        }
        if summary.isPassing && summary.optionalRemaining > 0 {
            return "The required tests pass. The remaining ones are quick and are what make an app feel finished."
        }
        if summary.isPassing {
            return "Everything passed on a real iPhone. That's more than most first submissions can say."
        }
        return "Open \(appName) on this iPhone and work down the list. Nobody has checked that it works yet — you're the first."
    }

    // MARK: Tests

    private func areaSection(_ area: TestCase.Area, _ tests: [TestCase]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(area.rawValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(area.blurb)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            ForEach(tests) { test in
                row(test)
            }
        }
    }

    private func row(_ test: TestCase) -> some View {
        let outcome = results[test.id]?.outcome
        let isOpen = open == test.id
        return GlassSurface(tier: isOpen ? .deep : .raised, corner: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Haptics.selection()
                    Motion.run(.spring(response: 0.32)) { open = isOpen ? nil : test.id }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: outcome == .passed ? "checkmark.circle.fill"
                              : outcome == .failed ? "xmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(outcome == .passed ? LiquidGlass.success
                                             : outcome == .failed ? LiquidGlass.error
                                             : LiquidGlass.primaryText.opacity(0.35))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(test.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(test.required ? "Required" : "Advised")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundStyle(test.required ? LiquidGlass.warning : LiquidGlass.primaryText.opacity(0.6))
                                .background((test.required ? LiquidGlass.warning : Color.white).opacity(0.14), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.4))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(test.title). \(test.required ? "Required" : "Advised"). \(outcomeLabel(outcome))")
                .accessibilityHint(isOpen ? "Collapses this test" : "Shows what to do")

                if isOpen {
                    detail(test, outcome: outcome)
                        .transition(.opacity)
                }
            }
            .padding(14)
        }
    }

    private func outcomeLabel(_ outcome: TestOutcome?) -> String {
        switch outcome {
        case .passed: "Works"
        case .failed: "Didn't work"
        case nil: "Not tried yet"
        }
    }

    private func detail(_ test: TestCase, outcome: TestOutcome?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            labelled("Do this", test.how)
            labelled("You should see", test.expect)
            labelled("Why it matters", test.why)

            HStack(spacing: 10) {
                verdictButton("Works", symbol: "checkmark", tint: LiquidGlass.success, selected: outcome == .passed) {
                    notes[test.id] = nil
                    onResult(test.id, TestResult(outcome: .passed))
                    Haptics.success()
                    advance(from: test)
                }
                verdictButton("Didn't work", symbol: "xmark", tint: LiquidGlass.error, selected: outcome == .failed) {
                    onResult(test.id, TestResult(outcome: .failed, note: notes[test.id] ?? results[test.id]?.note))
                    Haptics.warning()
                    noteFocused = test.id
                }
            }

            if outcome == .failed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What happened?")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(0.8)
                    TextField("e.g. it froze on a white screen", text: noteBinding(test), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .focused($noteFocused, equals: test.id)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
                        .accessibilityLabel("What happened")
                    Text("One line is enough. It's passed to the next build exactly as you write it.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if outcome != nil {
                Button {
                    notes[test.id] = nil
                    onResult(test.id, nil)
                    Haptics.selection()
                } label: {
                    Text("Clear this result")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Saves as the user types, so a note is never lost to a dismissed
    /// keyboard or a closed sheet.
    private func noteBinding(_ test: TestCase) -> Binding<String> {
        Binding(
            get: { notes[test.id] ?? results[test.id]?.note ?? "" },
            set: { text in
                notes[test.id] = text
                onResult(test.id, TestResult(outcome: .failed, note: text))
            }
        )
    }

    private func advance(from test: TestCase) {
        var after = results
        after[test.id] = TestResult(outcome: .passed)
        let next = TestPlan.next(in: plan, results: after)?.id
        Motion.run(.spring(response: 0.35)) { open = next }
    }

    private func verdictButton(
        _ title: String, symbol: String, tint: Color, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? Color.white : tint)
                .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.45)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func labelled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.8)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The checkpoint between testing and the store page: carry on, or
/// rebuild with what testing found.
struct ASCTestVerdictCard: View {
    let plan: [TestCase]
    let results: [String: TestResult]
    var onReady: () -> Void
    var onRebuild: (_ extraFindings: String) -> Void
    var onBackToTests: () -> Void

    @State private var testerFindings: String = ""

    private var summary: TestPlan.Summary { TestPlan.summary(of: plan, results: results) }
    private var failures: [(test: TestCase, note: String?)] { TestPlan.failures(in: plan, results: results) }
    private var hasTesterFindings: Bool {
        !testerFindings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary.headline)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)

                if !failures.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(failures, id: \.test.id) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(LiquidGlass.error)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.test.title)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText)
                                    if let note = item.note {
                                        Text(note)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Did your tester run into anything?")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    TextField("e.g. couldn't find how to add a beach", text: $testerFindings, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
                        .accessibilityLabel("What your tester ran into")
                    Text("Leave it empty if they got through without trouble.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                }

                if !summary.isComplete {
                    Text("\(summary.requiredRemaining) required test\(summary.requiredRemaining == 1 ? " hasn't" : "s haven't") been tried yet. This step opens when they have.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Back to the test plan", systemImage: "arrow.uturn.backward", style: .filled) {
                        onBackToTests()
                    }
                } else if !failures.isEmpty || hasTesterFindings {
                    PrimaryButton(title: "Rebuild with these fixed", systemImage: "wand.and.stars", style: .filled) {
                        onRebuild(testerFindings)
                    }
                    .accessibilityHint("Starts a new build that is told about every problem found. You'll upload and test that build.")
                    Text("A rebuild takes a few minutes. Then you archive it in Xcode again and re-run the tests — your Xcode setup and store page work are kept.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PrimaryButton(title: "It's ready — on to the store page", systemImage: "checkmark.seal.fill", style: .filled) {
                        onReady()
                    }
                }
            }
            .padding(18)
        }
    }
}
