import SwiftUI

/// Lets an owner rate and review a title they've purchased.
struct WriteReviewView: View {
    let item: MediaItem
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 0
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        PosterArt(item: item, showsTitle: false).frame(width: 56, height: 82)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                            Text("by \(item.creator)").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }

                    VStack(spacing: 8) {
                        Text("Your rating").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        StarPicker(rating: $rating)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Review").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                            Spacer()
                            Text("\(text.count)/\(MarketplaceStore.maxReviewLength)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(text.count > MarketplaceStore.maxReviewLength ? Theme.warning : Theme.inkFaint)
                        }
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                            .foregroundStyle(Theme.ink)
                            .font(.system(size: 14))
                            .onChange(of: text) { _, new in
                                if new.count > MarketplaceStore.maxReviewLength {
                                    text = String(new.prefix(MarketplaceStore.maxReviewLength))
                                }
                            }
                    }

                    PrimaryButton(title: "Post review", systemImage: "paperplane.fill",
                                  enabled: rating > 0 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        if store.addReview(itemID: item.id, rating: rating, text: text) {
                            Haptics.success()
                            dismiss()
                        } else {
                            Haptics.warning()
                        }
                    }
                }
                .padding(18)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Write a review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            if let mine = store.reviewList(for: item.id).first(where: { $0.author == (store.accountName.trimmed.isEmpty ? "You" : store.accountName.trimmed) }) {
                rating = mine.rating
                text = mine.text
            }
        }
    }
}
