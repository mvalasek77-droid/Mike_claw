import SwiftUI

// MARK: - CompanionSelectionView
//
// Full-screen companion picker used inside onboarding (Step 3).
// Shows 3 female + 3 male cards. User can filter by gender.
// Tapping a card shows a detail sheet. Confirming stores the selection.

struct CompanionSelectionView: View {
    @ObservedObject var persona: UserPersona
    @State private var genderFilter: CompanionGender? = nil
    @State private var detailCompanion: CompanionPersonality? = nil

    private var mode: RelationshipMode { persona.relationshipMode }

    private var filtered: [CompanionPersonality] {
        let base: [CompanionPersonality]
        switch genderFilter {
        case .female: base = CompanionPersonality.allFemale
        case .male:   base = CompanionPersonality.allMale
        case nil:     base = CompanionPersonality.all
        }
        // Featured companions for the current mode appear first
        return base.sorted { a, b in
            let af = a.isFeatured(for: mode), bf = b.isFeatured(for: mode)
            if af == bf { return false }
            return af && !bf
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("💛 Choose your companion")
                    .font(BCFont.caption())
                    .foregroundColor(.BC.accent)
                Text("Who do you want by your side?")
                    .font(BCFont.title())
                    .foregroundColor(.BC.textPrimary)

                // Mode-aware subtitle
                HStack(spacing: 6) {
                    Text(mode.emoji)
                    Text("\(mode.label) mode — best matches shown first.")
                        .font(BCFont.body(13))
                        .foregroundColor(.BC.textSecondary)
                }
            }
            .padding(.horizontal, BCSizing.spacingLG)
            .padding(.top, BCSizing.spacingMD)
            .padding(.bottom, BCSizing.spacingMD)

            // Gender filter pills
            HStack(spacing: 10) {
                FilterPill(label: "All",    selected: genderFilter == nil)   { genderFilter = nil }
                FilterPill(label: "Female", selected: genderFilter == .female) { genderFilter = .female }
                FilterPill(label: "Male",   selected: genderFilter == .male)   { genderFilter = .male }
            }
            .padding(.horizontal, BCSizing.spacingLG)
            .padding(.bottom, BCSizing.spacingMD)

            // Companion cards grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    ForEach(filtered) { companion in
                        CompanionCard(
                            companion: companion,
                            isSelected: persona.selectedCompanionID == companion.id,
                            isFeaturedForMode: companion.isFeatured(for: mode)
                        ) {
                            detailCompanion = companion
                        }
                    }
                }
                .padding(.horizontal, BCSizing.spacingLG)
                .padding(.bottom, BCSizing.spacingXL)
                .animation(.spring(response: 0.35), value: genderFilter)
            }
        }
        .sheet(item: $detailCompanion) { companion in
            CompanionDetailSheet(companion: companion, isSelected: persona.selectedCompanionID == companion.id) {
                withAnimation(.spring(response: 0.3)) {
                    persona.selectedCompanionID = companion.id
                }
                detailCompanion = nil
            }
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            BCHaptic.light()
            action()
        } label: {
            Text(label)
                .font(BCFont.caption(13))
                .foregroundColor(selected ? .black : .BC.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? Color.BC.accent : Color.BC.surfaceRaised)
                .cornerRadius(20)
                .overlay(
                    Capsule()
                        .strokeBorder(selected ? Color.clear : Color.BC.border, lineWidth: 1)
                )
        }
        .buttonStyle(BCButtonStyle(haptic: .none))
        .accessibilityLabel(selected ? "\(label), selected" : label)
    }
}

// MARK: - CompanionCard
//
// Full-portrait photo-card design. The illustrated portrait fills the
// entire card; name, tagline and tags overlay a bottom gradient.

private struct CompanionCard: View {
    let companion: CompanionPersonality
    let isSelected: Bool
    var isFeaturedForMode: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            BCHaptic.light()
            action()
        } label: {
            ZStack(alignment: .bottom) {

                // ── Full-card portrait ─────────────────────────────────
                IllustratedPortraitView(
                    gender:       companion.gender,
                    companionId:  companion.id,
                    accentColor:  companion.accentColor,
                    size:         220,
                    clipToCircle: false
                )
                .frame(height: 240)
                .clipped()
                .opacity(isFeaturedForMode ? 1.0 : 0.88)

                // ── Bottom info gradient overlay ───────────────────────
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint:   .bottom
                )
                .frame(height: 240)

                // ── Info text ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(companion.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text(isSelected ? "Current" : "View")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isSelected ? companion.accentColor : .white.opacity(0.76))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.24))
                            .cornerRadius(10)
                    }

                    Text(companion.tagline)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        ForEach(companion.personalityTags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(companion.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(companion.accentColor.opacity(0.22))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(12)

                // ── Top badges ────────────────────────────────────────
                VStack {
                    HStack {
                        Text(companion.genderLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        Spacer()
                        if isFeaturedForMode {
                            Text("★ Best match")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(companion.accentColor.opacity(0.88))
                                .cornerRadius(6)
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: 240)
            .cornerRadius(BCSizing.radiusLG)
            .overlay(
                RoundedRectangle(cornerRadius: BCSizing.radiusLG)
                    .strokeBorder(
                        isSelected ? companion.accentColor : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(
                color: isSelected ? companion.accentColor.opacity(0.35) : .black.opacity(0.22),
                radius: isSelected ? 10 : 5, y: 4
            )
            .animation(.spring(response: 0.28), value: isSelected)
        }
        .buttonStyle(BCButtonStyle(haptic: .none))
        .accessibilityLabel("\(companion.name), \(companion.tagline)\(isSelected ? ", currently selected" : "")")
        .accessibilityHint("Double-tap to view details")
    }
}

// MARK: - CompanionDetailSheet

struct CompanionDetailSheet: View {
    let companion: CompanionPersonality
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.BC.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {

                        // Large avatar
                        CompanionAvatarView(companion: companion, size: .detail)
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .clipped()

                        // Accent gradient overlay
                        LinearGradient(
                            colors: [companion.accentColor.opacity(0.3), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(height: 100)
                        .offset(y: -100)

                        VStack(alignment: .leading, spacing: BCSizing.spacingLG) {

                            // Name + tags
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(companion.name)
                                        .font(BCFont.title(28))
                                        .foregroundColor(.BC.textPrimary)
                                    Spacer()
                                    Text(companion.genderLabel)
                                        .font(BCFont.caption(12))
                                        .foregroundColor(companion.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(companion.accentColor.opacity(0.15))
                                        .cornerRadius(8)
                                }
                                Text(companion.tagline)
                                    .font(BCFont.headline())
                                    .foregroundColor(.BC.textSecondary)
                                    .italic()
                            }

                            // Bio
                            Text(companion.bioLong)
                                .font(BCFont.body())
                                .foregroundColor(.BC.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            // Love language badge
                            HStack(spacing: 10) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(companion.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Love Language")
                                        .font(BCFont.caption(11))
                                        .foregroundColor(.BC.textMuted)
                                    Text(companion.dominantLoveLanguage.displayName)
                                        .font(BCFont.headline())
                                        .foregroundColor(.BC.textPrimary)
                                }
                            }
                            .padding(BCSizing.spacingMD)
                            .background(Color.BC.surfaceRaised)
                            .cornerRadius(BCSizing.radiusMD)

                            // All personality tags
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Personality")
                                    .font(BCFont.caption(12))
                                    .foregroundColor(.BC.textMuted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                FlowLayout(spacing: 8) {
                                    ForEach(companion.personalityTags, id: \.self) { tag in
                                        Text(tag)
                                            .font(BCFont.body(13))
                                            .foregroundColor(companion.accentColor)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(companion.accentColor.opacity(0.12))
                                            .cornerRadius(20)
                                    }
                                }
                            }

                            // First message preview
                            VStack(alignment: .leading, spacing: 8) {
                                Text("First thing \(companion.gender == .female ? "she'll" : "he'll") say to you")
                                    .font(BCFont.caption(12))
                                    .foregroundColor(.BC.textMuted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                Text("\"\(companion.introMessage)\"")
                                    .font(BCFont.body())
                                    .foregroundColor(.BC.textPrimary)
                                    .italic()
                                    .padding(BCSizing.spacingMD)
                                    .background(companion.accentColor.opacity(0.08))
                                    .cornerRadius(BCSizing.radiusMD)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                                            .strokeBorder(companion.accentColor.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            // Select button
                            Button {
                                BCHaptic.success()
                                onSelect()
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text(isSelected ? "Keep \(companion.name)" : "Choose \(companion.name)")
                                        .font(BCFont.headline())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(
                                        colors: [companion.accentColor, companion.accentColor.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(BCSizing.radiusLG)
                                .overlay(
                                    RoundedRectangle(cornerRadius: BCSizing.radiusLG)
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .shadow(
                                    color: companion.accentColor.opacity(0.28),
                                    radius: 10,
                                    x: 0,
                                    y: 5
                                )
                            }
                            .padding(.top, BCSizing.spacingSM)
                        }
                        .padding(BCSizing.spacingLG)
                        .offset(y: -60)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                        .foregroundColor(.BC.textSecondary)
                }
            }
        }
    }
}

// MARK: - CompanionAvatarView
//
// Renders the companion's photo. Falls back to a stylized placeholder
// if the asset isn't in Assets.xcassets yet.

enum AvatarSize { case card, detail, chat }

struct CompanionAvatarView: View {
    let companion: CompanionPersonality
    let size: AvatarSize

    @ObservedObject private var photoStore = CompanionPhotoStore.shared

    private var cornerRadius: CGFloat {
        size == .card ? 0 : (size == .chat ? 22 : 0)
    }

    var body: some View {
        if let photo = photoStore.photo(for: companion.id) {
            // User-supplied photo always wins
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .cornerRadius(cornerRadius)
        } else if UIImage(named: companion.avatarImageName) != nil {
            Image(companion.avatarImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .cornerRadius(cornerRadius)
        } else {
            // Illustrated placeholder — no asset in catalog yet
            PlaceholderAvatarView(companion: companion, size: size)
                .cornerRadius(cornerRadius)
        }
    }
}

private struct PlaceholderAvatarView: View {
    let companion: CompanionPersonality
    let size: AvatarSize

    var body: some View {
        ZStack {
            // Illustrated portrait — drawn fully in SwiftUI, no assets needed
            CompanionPortraitView(companion: companion, size: size)

            // Name badge overlay (card + detail sizes only)
            if size != .chat {
                VStack {
                    Spacer()
                    HStack {
                        Text(companion.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(10)
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - FlowLayout (wrapping tag cloud)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.maxHeight } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.view.sizeThatFits(.unspecified)
                item.view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.maxHeight + spacing
        }
    }

    private struct Row {
        var items: [(view: LayoutSubview, width: CGFloat)] = []
        var maxHeight: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? 300
        var rows: [Row] = [Row()]
        var currentWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
                currentWidth = 0
            }
            rows[rows.count - 1].items.append((view, size.width))
            rows[rows.count - 1].maxHeight = max(rows[rows.count - 1].maxHeight, size.height)
            currentWidth += size.width + spacing
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

// MARK: - LoveLanguage display name

extension LoveLanguage {
    var displayName: String {
        switch self {
        case .wordsOfAffirmation: return "Words of Affirmation"
        case .actsOfService:      return "Acts of Service"
        case .receivingGifts:     return "Receiving Gifts"
        case .qualityTime:        return "Quality Time"
        case .physicalTouch:      return "Physical Touch (expressed verbally)"
        }
    }
}
