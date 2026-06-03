import SwiftUI

/// Standard portrait poster used inside horizontal browse rows.
struct MediaCard: View {
    let item: MediaItem
    var width: CGFloat = 124
    var onTap: () -> Void

    @EnvironmentObject private var store: MarketplaceStore

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    PosterArt(item: item)
                        .frame(width: width, height: width * 1.48)
                        .opacity(store.isComingSoon(item) ? 0.7 : 1)
                    if store.isComingSoon(item) {
                        Text("PREMIERING").font(.system(size: 7.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.kdp)).padding(6)
                    } else {
                        ScoreBadge(score: item.commercialScore, compact: true).padding(6)
                    }
                    if store.owns(item) {
                        ownedTag.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                if store.isComingSoon(item) {
                    Text("Premiering soon").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.kdp)
                } else {
                    Text(store.owns(item) ? item.priceLabel : String(format: "$%.2f", store.effectivePrice(for: item)))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(store.owns(item) ? Theme.success
                                         : (store.priceDeltaPercent(for: item) > 0 ? Theme.warning
                                            : store.priceDeltaPercent(for: item) < 0 ? Theme.success : Theme.inkSoft))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.categoryLabel) by \(item.creator)")
        .accessibilityValue(store.owns(item) ? "In your library" : "\(item.priceLabel), AI Editor score \(item.commercialScore)")
        .accessibilityAddTraits(.isButton)
    }

    private var ownedTag: some View {
        Text("IN LIBRARY")
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Theme.success))
    }
}

/// A horizontally scrolling, titled row of posters.
struct MediaRow: View {
    let title: String
    var subtitle: String? = nil
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, subtitle: subtitle).screenPadding()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            MediaCard(item: item) { onSelect(item) }
                        }
                    }
                    .screenPadding()
                }
            }
        }
    }
}

/// The Top-10 row with oversized rank numerals behind each poster.
struct RankedRow: View {
    let title: String
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: "Most purchased this week").screenPadding()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { onSelect(item) } label: {
                            HStack(alignment: .bottom, spacing: -14) {
                                Text("\(index + 1)")
                                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.16))
                                    .frame(width: 60, alignment: .leading)
                                PosterArt(item: item)
                                    .frame(width: 112, height: 166)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                }
                .screenPadding()
            }
        }
    }
}
