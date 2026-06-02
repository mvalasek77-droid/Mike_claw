import SwiftUI

/// The KDP-style "Bookshelf": a creator's pipeline of titles plus the entry
/// point to register a new work.
struct PublishHomeView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var showCreate = false
    @State private var createID = UUID()   // forces SubmitWorkView to reset each time
    @State private var showPartners = false
    @State private var openSubmission: Submission?
    @State private var showStripeGate = false
    @State private var showPayoutSetup = false

    var body: some View {
        ZStack {
            // Warm KDP backdrop on the creation side.
            LinearGradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.04), Theme.bg],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            LinearGradient(colors: [Theme.kdp.opacity(0.20), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    PrimaryButton(title: "Register a new title", systemImage: "plus",
                                  tint: Theme.kdp) {
                        // Stripe gate: a first-time publisher has to set up
                        // payouts BEFORE they can submit anything. Without
                        // this we'd accept work we have no way to pay them
                        // for, which is the worst kind of unfinished UX.
                        if store.payoutConnected {
                            createID = UUID()
                            showCreate = true
                        } else {
                            showStripeGate = true
                        }
                    }
                    .screenPadding()

                    earnBanner

                    if store.submissions.isEmpty {
                        emptyState
                    } else {
                        pipeline
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .fullScreenCover(isPresented: $showCreate) {
            SubmitWorkView().id(createID)
        }
        .sheet(isPresented: $showPartners) { PartnerProgramView() }
        .sheet(item: $openSubmission) { sub in
            SubmissionDetailView(submissionID: sub.id)
        }
        .sheet(isPresented: $showPayoutSetup) {
            PayoutConfigView()
        }
        .alert("Set up payouts first", isPresented: $showStripeGate) {
            Button("Set up payouts") { showPayoutSetup = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Before you publish anything, connect a Stripe account so we have a way to send you your 85% share of every sale. Takes about 5 minutes. You only do this once.")
        }
    }

    private var earnBanner: some View {
        Button { showPartners = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earn real dollars").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("Keep 85% of net proceeds · invite AI models to contribute")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerL).fill(Theme.success.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerL).strokeBorder(Theme.success.opacity(0.3), lineWidth: 0.8))
            .screenPadding()
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Publish")
                    .font(.displayL)
                    .foregroundStyle(Theme.ink)
                Text("KDP")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.kdp))
            }
            Text("Register your AI-made work, pass the 85% commercial bar, and go live.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .screenPadding()
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your bookshelf", subtitle: "\(store.submissions.count) title\(store.submissions.count == 1 ? "" : "s")")
                .screenPadding()
            // SwiftUI's swipe actions need List — wrap the rows.
            // We keep the look close to LazyVStack by using .plain list style
            // and removing row insets / dividers.
            List {
                ForEach(store.submissions) { sub in
                    Button { openSubmission = sub } label: {
                        ShelfRow(submission: sub)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Only allow deletion of non-live entries — a live
                        // (.accepted with publishedItemID) submission has to
                        // go through admin so buyers' libraries stay clean.
                        if sub.publishedItemID == nil {
                            Button(role: .destructive) {
                                store.removeSubmission(sub.id)
                                Haptics.warning()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(minHeight: CGFloat(max(1, store.submissions.count)) * 96)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 50))
                .foregroundStyle(Theme.kdp.opacity(0.8))
            Text("Your bookshelf is empty")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Register your first AI novel, album or film. The AI Editor will review it and, if it clears 85% commercial quality, publish it to the marketplace.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 50)
    }
}

private struct ShelfRow: View {
    let submission: Submission

    private var statusColor: Color {
        switch submission.status {
        case .accepted: return Theme.success
        case .rejected: return Theme.warning
        case .reviewing: return Theme.accent
        case .draft: return Theme.inkFaint
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerS)
                    .fill(submission.draft.type.accent.opacity(0.22))
                Image(systemName: submission.draft.type.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(submission.draft.type.accent)
            }
            .frame(width: 54, height: 76)

            VStack(alignment: .leading, spacing: 4) {
                Text(submission.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(submission.draft.type.title) · \(submission.draft.genre.isEmpty ? "—" : submission.draft.genre)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(submission.status.rawValue)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                    if let score = submission.review?.overall {
                        Text("· \(score)/100")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        // Single VoiceOver element per row: title + type + status.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(submission.title), \(submission.draft.type.title), \(submission.status.rawValue)"))
        .accessibilityHint(Text("Open submission details"))
    }
}
