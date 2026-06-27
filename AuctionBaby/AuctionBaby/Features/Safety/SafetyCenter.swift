import SwiftUI

/// Trust & safety hub — date-safety guidance, how reporting works, and the
/// verification nudge. The layer serious daters (and App Review) expect.
struct SafetyCenterView: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    private let tips: [(String, String, String)] = [
        ("video", "Meet in public, first time", "Pick a busy bar or restaurant. Tell a friend where you'll be."),
        ("creditcard", "Settle money your way", "A bid is a letter of intent — never wire money or send deposits before a date. Real bidders pay in person."),
        ("checkmark.seal.fill", "Look for the blue check", "Verified profiles have matched a live selfie to their photos. Copycats never can."),
        ("sparkles", "Spot the Copycats", "AI lure profiles are labelled “Copycat · AI”. Bidding on them hurts your reputation — and they're not real people."),
        ("flag", "Report anything off", "Use Report & Block on any profile or chat. Reported users are removed from your floor immediately."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard(tint: Theme.verify) {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled").font(.system(size: 26, weight: .bold))
                                .foregroundStyle(Theme.verify)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your safety comes first")
                                    .font(.system(size: 16, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                                Text("Date smart. Trust the checks. Report the rest.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    ForEach(tips, id: \.1) { tip in
                        GlassSurface(corner: Theme.cornerL) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: tip.0).font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.gold).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tip.1).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                                    Text(tip.2).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                        }
                    }
                    if !store.blockedIDs.isEmpty {
                        Text("\(store.blockedIDs.count) profile\(store.blockedIDs.count == 1 ? "" : "s") blocked")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("Safety Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
            }
        }
    }
}

/// Reason picker for reporting + blocking a profile.
struct ReportSheet: View {
    let profile: Profile
    var onReported: () -> Void
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    private let reasons = ["Fake / not a real person", "Inappropriate content",
                           "Harassment or abuse", "Didn't pay the bid (deadbeat)",
                           "Spam or scam", "Something else"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Report \(profile.name)")
                        .font(.system(size: 18, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                        .padding(.top, 8)
                    Text("They'll be removed from your floor and won't be able to reach you. Reports are reviewed by our team.")
                        .font(.system(size: 13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            store.blockAndReport(profile, reason: reason)
                            dismiss()
                            onReported()
                        } label: {
                            HStack {
                                Text(reason).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.inkFaint)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 20)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("Report & Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
