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

    private var filtered: [CompanionPersonality] {
        switch genderFilter {
        case .female: return CompanionPersonality.allFemale
        case .male:   return CompanionPersonality.allMale
        case nil:     return CompanionPersonality.all
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("💛 Choose your companion")
                    .font(OCFont.caption())
                    .foregroundColor(.OC.accent)
                Text("Who do you want by your side?")
                    .font(OCFont.title())
                    .foregroundColor(.OC.textPrimary)
                Text("Your companion learns about you and grows with you over time.")
                    .font(OCFont.body())
                    .foregroundColor(.OC.textSecondary)
            }
            .padding(.horizontal, OCSizing.spacingLG)
            .padding(.top, OCSizing.spacingMD)
            .padding(.bottom, OCSizing.spacingMD)

            // Gender filter pills
            HStack(spacing: 10) {
                FilterPill(label: "All",    selected: genderFilter == nil)   { genderFilter = nil }
                FilterPill(label: "Female", selected: genderFilter == .female) { genderFilter = .female }
                FilterPill(label: "Male",   selected: genderFilter == .male)   { genderFilter = .male }
            }
            .padding(.horizontal, OCSizing.spacingLG)
            .padding(.bottom, OCSizing.spacingMD)

            // Companion cards grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    ForEach(filtered) { companion in
                        CompanionCard(
                            companion: companion,
                            isSelected: persona.selectedCompanionID == companion.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                persona.selectedCompanionID = companion.id
                            }
                            detailCompanion = companion
                        }
                    }
                }
                .padding(.horizontal, OCSizing.spacingLG)
                .padding(.bottom, OCSizing.spacingXL)
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
        Button(action: action) {
            Text(label)
                .font(OCFont.caption(13))
                .foregroundColor(selected ? .black : .OC.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? Color.OC.accent : Color.OC.surfaceRaised)
                .cornerRadius(20)
                .overlay(
                    Capsule()
                        .strokeBorder(selected ? Color.clear : Color.OC.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - CompanionCard

private struct CompanionCard: View {
    let companion: CompanionPersonality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {

                // Avatar area
                ZStack(alignment: .bottomLeading) {
                    CompanionAvatarView(companion: companion, size: .card)
                        .frame(height: 160)
                        .clipped()

                    // Gender badge
                    Text(companion.genderLabel)
                        .font(OCFont.caption(10))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(6)
                        .padding(8)
                }

                // Info area
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(companion.name)
                            .font(OCFont.headline())
                            .foregroundColor(.OC.textPrimary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(companion.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text(companion.tagline)
                        .font(OCFont.body(12))
                        .foregroundColor(.OC.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Personality tags
                    HStack(spacing: 4) {
                        ForEach(companion.personalityTags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(OCFont.caption(10))
                                .foregroundColor(companion.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(companion.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .background(Color.OC.surfaceRaised)
            }
            .cornerRadius(OCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                    .strokeBorder(
                        isSelected ? companion.accentColor : Color.OC.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1)
            .shadow(color: isSelected ? companion.accentColor.opacity(0.25) : .clear, radius: 8, y: 4)
        }
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
                Color.OC.background.ignoresSafeArea()

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

                        VStack(alignment: .leading, spacing: OCSizing.spacingLG) {

                            // Name + tags
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(companion.name)
                                        .font(OCFont.title(28))
                                        .foregroundColor(.OC.textPrimary)
                                    Spacer()
                                    Text(companion.genderLabel)
                                        .font(OCFont.caption(12))
                                        .foregroundColor(companion.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(companion.accentColor.opacity(0.15))
                                        .cornerRadius(8)
                                }
                                Text(companion.tagline)
                                    .font(OCFont.headline())
                                    .foregroundColor(.OC.textSecondary)
                                    .italic()
                            }

                            // Bio
                            Text(companion.bioLong)
                                .font(OCFont.body())
                                .foregroundColor(.OC.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            // Love language badge
                            HStack(spacing: 10) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(companion.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Love Language")
                                        .font(OCFont.caption(11))
                                        .foregroundColor(.OC.textMuted)
                                    Text(companion.dominantLoveLanguage.displayName)
                                        .font(OCFont.headline())
                                        .foregroundColor(.OC.textPrimary)
                                }
                            }
                            .padding(OCSizing.spacingMD)
                            .background(Color.OC.surfaceRaised)
                            .cornerRadius(OCSizing.radiusMD)

                            // All personality tags
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Personality")
                                    .font(OCFont.caption(12))
                                    .foregroundColor(.OC.textMuted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                FlowLayout(spacing: 8) {
                                    ForEach(companion.personalityTags, id: \.self) { tag in
                                        Text(tag)
                                            .font(OCFont.body(13))
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
                                    .font(OCFont.caption(12))
                                    .foregroundColor(.OC.textMuted)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                Text("\"\(companion.introMessage)\"")
                                    .font(OCFont.body())
                                    .foregroundColor(.OC.textPrimary)
                                    .italic()
                                    .padding(OCSizing.spacingMD)
                                    .background(companion.accentColor.opacity(0.08))
                                    .cornerRadius(OCSizing.radiusMD)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                                            .strokeBorder(companion.accentColor.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            // Select button
                            Button(action: {
                                onSelect()
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "heart.fill")
                                    Text(isSelected ? "Selected ✓" : "Choose \(companion.name)")
                                        .font(OCFont.headline())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isSelected ? Color.OC.success : companion.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(OCSizing.radiusLG)
                            }
                            .padding(.top, OCSizing.spacingSM)
                        }
                        .padding(OCSizing.spacingLG)
                        .offset(y: -60)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                        .foregroundColor(.OC.textSecondary)
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

    private var cornerRadius: CGFloat {
        size == .card ? 0 : (size == .chat ? 22 : 0)
    }

    var body: some View {
        if UIImage(named: companion.avatarImageName) != nil {
            Image(companion.avatarImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .cornerRadius(cornerRadius)
        } else {
            // Stylised placeholder until real photos are added
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
