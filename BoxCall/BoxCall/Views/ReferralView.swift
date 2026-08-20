import SwiftUI

struct ReferralView: View {
    @ObservedObject var service = ReferralService.shared
    @State private var codeInput: String = ""
    @State private var err: String?
    @State private var showRedeemedToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                shareYourCode
                enterACode
                howItWorks
            }
            .padding()
        }
        .navigationTitle("Invite friends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bring the crowd.")
                .font(.title2.bold())
            Text("Both sides get **\(Int(ReferralService.bonusPerSide)) RC** when someone new redeems your code. Max \(ReferralService.maxRedemptionsPerCode) redemptions per code — enough to bring your group chat, not enough to farm.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var shareYourCode: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your code").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text(service.myCode)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .kerning(4)
                    .foregroundStyle(.orange)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(service.redemptionsMade)")
                        .font(.title3.weight(.bold)).monospacedDigit()
                    Text("redeemed").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = service.myCode
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    Sharer.share(
                        Text("Join BoxCall — my code is \(service.myCode). Get 500 free Reel Coins."),
                        message: "Join BoxCall — my code is \(service.myCode). Get 500 free Reel Coins.")
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))
    }

    private var enterACode: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Got a code?").font(.headline)
            HStack {
                TextField("6-character code", text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button {
                    redeem()
                } label: {
                    Text("Redeem").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || service.didRedeem)
            }
            if let err {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if service.didRedeem {
                Label("You've already redeemed a code.",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it works").font(.headline)
            bullet("Share your code with a friend.")
            bullet("They install BoxCall and enter your code on this screen.")
            bullet("You BOTH instantly get \(Int(ReferralService.bonusPerSide)) RC.")
            bullet("Cap: \(ReferralService.maxRedemptionsPerCode) redemptions per code — enough for a group chat, not a farm.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle.fill").font(.system(size: 4)).padding(.top, 6)
            Text(text)
        }
    }

    @MainActor
    private func redeem() {
        do {
            try service.redeem(code: codeInput)
            err = nil
            codeInput = ""
        } catch {
            err = error.localizedDescription
        }
    }
}
