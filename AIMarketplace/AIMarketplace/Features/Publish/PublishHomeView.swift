import SwiftUI

/// The KDP-style "Bookshelf": a creator's pipeline of titles plus the entry
/// point to register a new work.
struct PublishHomeView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var showCreate = false
    @State private var openSubmission: Submission?

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
                                  tint: Theme.kdp) { showCreate = true }
                        .screenPadding()

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
            SubmitWorkView()
        }
        .sheet(item: $openSubmission) { sub in
            SubmissionDetailView(submissionID: sub.id)
        }
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
            LazyVStack(spacing: 12) {
                ForEach(store.submissions) { sub in
                    Button { openSubmission = sub } label: {
                        ShelfRow(submission: sub)
                    }
                    .buttonStyle(.plain)
                }
            }
            .screenPadding()
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
    }
}
