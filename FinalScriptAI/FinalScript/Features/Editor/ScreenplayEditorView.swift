import SwiftUI

/// The writing surface. The screenplay is modeled as an ordered list of typed
/// elements; each element renders with industry indentation and is editable in
/// place. Pressing return inside an element splits it into a new element whose
/// type is predicted from the current one (scene heading → action, character →
/// dialogue, …) — the "smart return" pros expect. A keyboard accessory bar
/// changes the current element's type and offers context-aware autocomplete.
struct ScreenplayEditorView: View {
    @Binding var screenplay: Screenplay
    @EnvironmentObject private var ai: AIService
    @EnvironmentObject private var entitlements: Entitlements
    @FocusState private var focusedID: UUID?
    @State private var focusMode = false
    @StateObject private var coach = LiveCoachController()
    @State private var showPaywall = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach($screenplay.elements) { $element in
                        ElementRow(element: $element,
                                   isFocused: focusedID == element.id)
                            .id(element.id)
                            .focused($focusedID, equals: element.id)
                            .onChange(of: element.text) { _, newValue in
                                handleTextChange(for: element.id, newValue: newValue)
                                triggerCoach(for: element.id)
                            }
                            .contextMenu { rowMenu(for: element.id) }
                    }

                    // Tap target below the last element to append.
                    Color.clear
                        .frame(height: 80)
                        .contentShape(Rectangle())
                        .onTapGesture { appendElement() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            .safeAreaInset(edge: .bottom) {
                if let id = focusedID, let index = index(of: id) {
                    EditorAccessoryBar(
                        element: $screenplay.elements[index],
                        suggestions: suggestions(for: screenplay.elements[index]),
                        onCycleType: { cycleType(at: index) },
                        onNewElement: { insertElement(after: id) },
                        onDelete: { deleteElement(id: id) },
                        onApplySuggestion: { applySuggestion($0, at: index) }
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                if coach.enabled { liveCoachBanner }
            }
            .animation(.easeInOut(duration: 0.25), value: coach.enabled)
            .animation(.easeInOut(duration: 0.25), value: coach.suggestions)
        }
        .overlay(alignment: .bottomTrailing) {
            if focusedID == nil { newSceneButton }
        }
        .overlay(alignment: .bottomLeading) {
            if focusedID == nil { liveCoachToggle }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Subviews

    private var newSceneButton: some View {
        Button {
            appendElement(type: .sceneHeading, text: "INT. ")
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(Palette.marqueeGradient, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .padding(20)
    }

    // MARK: - Live coach

    private var liveCoachToggle: some View {
        Button { toggleCoach() } label: {
            Image(systemName: coach.enabled ? "wand.and.stars" : "wand.and.stars.inverse")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(coach.enabled ? .black : Palette.accent)
                .frame(width: 44, height: 44)
                .background {
                    if coach.enabled {
                        Circle().fill(Palette.marqueeGradient)
                    } else {
                        Circle().fill(Color.black.opacity(0.25))
                            .overlay(Circle().stroke(Palette.accent.opacity(0.5), lineWidth: 1))
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .padding(.leading, 20)
        .padding(.bottom, 20)
        .accessibilityLabel(coach.enabled ? "Turn off live coach" : "Turn on live coach")
    }

    @ViewBuilder
    private var liveCoachBanner: some View {
        GlassCard(tier: .raised, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").foregroundStyle(Palette.accent)
                    Text("LIVE COACH").font(.labelSmall).foregroundStyle(Palette.accent)
                    Spacer()
                    if coach.isThinking {
                        ProgressView().scaleEffect(0.7)
                    }
                    Button { toggleCoach() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondaryText)
                    }
                }

                if coach.needsKey {
                    Text("Add your Anthropic API key in Settings to get live notes.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                } else if coach.suggestions.isEmpty {
                    Text(coach.isThinking ? "Reading the scene…" : "Keep writing — notes appear as you go.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(coach.suggestions) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: suggestion.lens.symbol)
                                .font(.caption)
                                .foregroundStyle(suggestion.lens.color)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.lens.title.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(suggestion.lens.color)
                                Text(suggestion.text)
                                    .font(.caption)
                                    .foregroundStyle(Palette.primaryText)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func toggleCoach() {
        if coach.enabled {
            coach.turnOff()
        } else {
            guard entitlements.isPro else { showPaywall = true; return }
            coach.enabled = true
            triggerCoach(for: focusedID ?? screenplay.elements.last?.id)
        }
        Haptics.tap()
    }

    /// Asks the coach to look at whatever scene the writer is currently in.
    private func triggerCoach(for id: UUID?) {
        guard coach.enabled, let id else { return }
        coach.analyze(scene: currentScene(around: id), screenplay: screenplay,
                      ai: ai, entitlements: entitlements)
    }

    /// The contiguous run of elements from the scene heading at or above `id`
    /// down to (but not including) the next scene heading — the unit the coach
    /// reasons about.
    private func currentScene(around id: UUID) -> [ScreenplayElement] {
        guard let idx = index(of: id) else { return [] }
        var start = idx
        while start > 0 && screenplay.elements[start].type != .sceneHeading { start -= 1 }
        var end = idx + 1
        while end < screenplay.elements.count && screenplay.elements[end].type != .sceneHeading { end += 1 }
        return Array(screenplay.elements[start..<end])
    }

    @ViewBuilder
    private func rowMenu(for id: UUID) -> some View {
        Menu("Change to") {
            ForEach(ElementType.allCases) { type in
                Button(type.displayName) { changeType(at: index(of: id), to: type) }
            }
        }
        Button(role: .destructive) { deleteElement(id: id) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Mutations

    private func index(of id: UUID) -> Int? {
        screenplay.elements.firstIndex { $0.id == id }
    }

    /// The color of the in-progress revision pass, if one has been started
    /// (Revisions tab). While a pass is active, edited/added elements get
    /// stamped with this color so a crew shooting from paper can see what
    /// changed — the actual point of tracking revisions at all.
    private var activeRevisionColor: String? { screenplay.revisions.last?.colorName }

    private func markRevised(at idx: Int) {
        guard let color = activeRevisionColor, screenplay.elements.indices.contains(idx) else { return }
        screenplay.elements[idx].revisionColor = color
    }

    /// Detects a return key press (a newline in the text) and splits the
    /// element, creating a successor whose type follows the smart-return rule.
    private func handleTextChange(for id: UUID, newValue: String) {
        guard let idx = index(of: id) else { return }
        markRevised(at: idx)
        guard newValue.contains("\n") else { return }
        let parts = newValue.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let before = String(parts.first ?? "")
        let after = parts.count > 1 ? String(parts[1]) : ""

        let currentType = screenplay.elements[idx].type
        screenplay.elements[idx].text = before

        let newElement = ScreenplayElement(type: currentType.successorOnReturn, text: after)
        screenplay.elements.insert(newElement, at: idx + 1)
        markRevised(at: idx + 1)
        focusedID = newElement.id
        Haptics.tap()
    }

    private func appendElement(type: ElementType = .action, text: String = "") {
        let new = ScreenplayElement(type: type, text: text)
        screenplay.elements.append(new)
        markRevised(at: screenplay.elements.count - 1)
        focusedID = new.id
    }

    private func insertElement(after id: UUID) {
        guard let idx = index(of: id) else { return }
        let successor = screenplay.elements[idx].type.successorOnReturn
        let new = ScreenplayElement(type: successor)
        screenplay.elements.insert(new, at: idx + 1)
        markRevised(at: idx + 1)
        focusedID = new.id
        Haptics.tap()
    }

    private func deleteElement(id: UUID) {
        guard let idx = index(of: id) else { return }
        let priorID = idx > 0 ? screenplay.elements[idx - 1].id : nil
        screenplay.elements.remove(at: idx)
        focusedID = priorID
    }

    private func changeType(at index: Int?, to type: ElementType) {
        guard let index else { return }
        screenplay.elements[index].type = type
        markRevised(at: index)
        Haptics.selection()
    }

    private func cycleType(at index: Int) {
        let next = screenplay.elements[index].type.nextCyclingType
        screenplay.elements[index].type = next
        markRevised(at: index)
        Haptics.selection()
    }

    private func applySuggestion(_ value: String, at index: Int) {
        screenplay.elements[index].text = value
        markRevised(at: index)
        Haptics.selection()
    }

    // MARK: - Smart type

    /// Context-aware completions for the element being edited.
    private func suggestions(for element: ScreenplayElement) -> [String] {
        let fragment = element.text.trimmingCharacters(in: .whitespaces).uppercased()
        switch element.type {
        case .character:
            let names = screenplay.characterNames
            if fragment.isEmpty { return Array(names.prefix(4)) }
            return names.filter { $0.hasPrefix(fragment) && $0 != fragment }.prefix(4).map { $0 }
        case .sceneHeading:
            if fragment.isEmpty || fragment == "INT" || fragment == "EXT" {
                return ["INT. ", "EXT. ", "INT./EXT. "]
            }
            // Suggest previously-used locations.
            let locations = priorLocations()
            return locations.filter { $0.uppercased().contains(fragment) }.prefix(4).map { $0 }
        case .transition:
            return ["CUT TO:", "SMASH CUT TO:", "DISSOLVE TO:", "MATCH CUT TO:"]
        default:
            return []
        }
    }

    private func priorLocations() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for e in screenplay.elements where e.type == .sceneHeading {
            let t = e.text.uppercased()
            guard !seen.contains(t), !t.isEmpty else { continue }
            seen.insert(t)
            result.append(t)
        }
        return result
    }
}
