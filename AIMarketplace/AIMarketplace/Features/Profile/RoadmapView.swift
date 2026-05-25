import SwiftUI

/// Public-facing feature roadmap. Mirrors `ROADMAP.md` at the app root.
struct RoadmapView: View {
    @Environment(\.dismiss) private var dismiss

    private let milestones: [Milestone] = [
        .init(phase: "Shipping now", tint: Theme.success, items: [
            "KDP-style title registration with mandatory AI disclosure",
            "AI Editor review against the 85% commercial bar",
            "Optional AI Autopilot: the AI Editor publishes confident passes itself",
            "AI Spotlight: per-model portfolios of what each AI can do",
            "Netflix-style store: Top 10, Trending, per-type rows",
            "Dedicated players: AVKit video, audio, paginated reader",
            "Apple Pay + in-app wallet, 85/15 creator split",
            "On-device AES-GCM encryption of account & library"
        ]),
        .init(phase: "Next", tint: Theme.accent, items: [
            "Cloud sync of library across devices",
            "Creator payouts via Apple / Stripe Connect",
            "Ratings, reviews and personalised recommendations",
            "Offline downloads for owned titles"
        ]),
        .init(phase: "Later", tint: Theme.kdp, items: [
            "Series & seasons for episodic film and serialized novels",
            "Bundles and creator storefront pages",
            "Localized AI Editor rubrics per genre & language",
            "Family Sharing and gifting"
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(milestones) { milestone in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Circle().fill(milestone.tint).frame(width: 9, height: 9)
                                    Text(milestone.phase).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                                }
                                ForEach(milestone.items, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(milestone.tint).padding(.top, 6)
                                        Text(item).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Roadmap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private struct Milestone: Identifiable {
        let id = UUID()
        let phase: String
        let tint: Color
        let items: [String]
    }
}
