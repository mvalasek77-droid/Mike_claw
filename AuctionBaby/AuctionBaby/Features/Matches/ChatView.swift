import SwiftUI

/// The conversation after a bid is accepted, plus the date lifecycle controls:
/// mark the date done, then leave a review.
struct ChatView: View {
    let matchID: UUID
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @State private var draft = ""
    @State private var showReview = false

    private var match: Match? { store.matches.first(where: { $0.id == matchID }) }

    var body: some View {
        Group {
            if let match {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                bidBanner(match)
                                ForEach(match.messages) { msg in
                                    MessageBubble(message: msg, otherName: match.other(for: store.role ?? .man).name)
                                        .id(msg.id)
                                }
                                readReceipt(match)
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .screenPadding().padding(.top, 10)
                        }
                        .onChange(of: match.messages.count) { _, _ in
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    composer(match)
                }
                .background(AppBackground())
                .sheet(isPresented: $showReview) {
                    RateDateView(match: match).presentationDetents([.large])
                        .presentationBackground(.ultraThinMaterial)
                }
            } else {
                EmptyStateView(icon: "bubble.left", title: "Match closed", message: "This conversation has ended.")
                    .background(AppBackground())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Black Card read receipt under your latest message.
    @ViewBuilder
    private func readReceipt(_ match: Match) -> some View {
        if storeKit.isSubscribed(to: .blackcard),
           match.phase == .chatting,
           match.messages.last?.fromMe == true {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: match.seenByOther ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(match.seenByOther ? "Seen" : "Delivered")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(match.seenByOther ? Theme.verify : Theme.inkFaint)
            }
            .padding(.trailing, 2)
        }
    }

    private func bidBanner(_ match: Match) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").font(.system(size: 11))
            Text("Accepted bid · \(Money.full(match.bid.amount))")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
            if match.bid.onCopycat {
                Text("· Copycat").foregroundStyle(Theme.copycat).font(.system(size: 12, weight: .heavy))
            }
        }
        .foregroundStyle(Theme.gold)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Theme.gold.opacity(0.14)))
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func composer(_ match: Match) -> some View {
        VStack(spacing: 10) {
            switch match.phase {
            case .chatting:
                HStack(spacing: 10) {
                    TextField("", text: $draft,
                              prompt: Text("Message…").foregroundStyle(Theme.inkFaint), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Capsule().fill(.white.opacity(0.08)))
                    Button {
                        store.send(draft, in: match); draft = ""
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.black).frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.goldGradient))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                if !match.bid.onCopycat {
                    GhostButton(title: "We went on the date", systemImage: "checkmark.circle") {
                        store.markDateDone(match)
                    }
                }
            case .dateDone:
                PrimaryButton(title: "Leave your review", systemImage: "star.fill",
                              gradient: store.role == .woman ? Theme.roseGradient : Theme.goldGradient) {
                    showReview = true
                }
            case .closed:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Text("Reviews posted · lot closed")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
        .screenPadding().padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let otherName: String

    var body: some View {
        if message.isSystem {
            Text(message.text)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else {
            HStack {
                if message.fromMe { Spacer(minLength: 50) }
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.fromMe ? .black : Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(message.fromMe ? AnyShapeStyle(Theme.goldGradient)
                                                 : AnyShapeStyle(Color.white.opacity(0.08)))
                    )
                if !message.fromMe { Spacer(minLength: 50) }
            }
            .accessibilityLabel("\(message.fromMe ? "You" : otherName): \(message.text)")
        }
    }
}
