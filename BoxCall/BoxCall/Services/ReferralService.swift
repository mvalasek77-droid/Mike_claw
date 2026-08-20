import Foundation
import Combine

/// Both-sides referrals: sharer and redeemer each get bonus RC when a
/// new user redeems a code. Local-only for now — the real system would
/// validate codes and cap RC through the backend to prevent farming.
@MainActor
final class ReferralService: ObservableObject {
    static let shared = ReferralService()

    /// Reel Coins granted to each side of a successful referral.
    static let bonusPerSide: Double = 500
    /// Maximum times ANY code can be redeemed (per referrer, per week
    /// in production; a lifetime cap here). Prevents farming.
    static let maxRedemptionsPerCode: Int = 25

    @Published private(set) var myCode: String
    @Published private(set) var redemptionsMade: Int      // how many people redeemed MY code
    @Published private(set) var didRedeem: Bool           // did *I* redeem someone else's code

    private let myCodeKey = "referral.myCode"
    private let redemptionsKey = "referral.redemptionsMade"
    private let didRedeemKey = "referral.didRedeem"

    private init() {
        if let existing = UserDefaults.standard.string(forKey: myCodeKey) {
            myCode = existing
        } else {
            myCode = ReferralService.generateCode()
            UserDefaults.standard.set(myCode, forKey: myCodeKey)
        }
        redemptionsMade = UserDefaults.standard.integer(forKey: redemptionsKey)
        didRedeem = UserDefaults.standard.bool(forKey: didRedeemKey)
    }

    enum RedeemError: LocalizedError {
        case alreadyRedeemed, selfReferral, invalidCode
        var errorDescription: String? {
            switch self {
            case .alreadyRedeemed: return "You've already redeemed a code. One per account."
            case .selfReferral: return "You can't redeem your own code."
            case .invalidCode: return "That code doesn't look right (6 letters/numbers)."
            }
        }
    }

    /// Redeem someone else's code. In production the backend validates
    /// the code exists and hasn't hit its cap; the sharer would also be
    /// credited via a server webhook. Local demo: just credit us.
    func redeem(code raw: String) throws {
        let code = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count == 6, code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw RedeemError.invalidCode
        }
        guard code != myCode else { throw RedeemError.selfReferral }
        guard !didRedeem else { throw RedeemError.alreadyRedeemed }

        didRedeem = true
        UserDefaults.standard.set(true, forKey: didRedeemKey)
        PortfolioService.shared.mutateUser {
            $0.reelCoins += ReferralService.bonusPerSide
        }
        RewardsService.shared.grant(
            xp: 25,
            reason: "Welcome bonus — thanks for joining via a referral")
        AnalyticsService.shared.track(.referralRedeemed(code: code))
    }

    /// Called locally when someone else told us their code was used.
    /// Real system: server webhook drives this.
    func creditSharerBonus() {
        guard redemptionsMade < ReferralService.maxRedemptionsPerCode else { return }
        redemptionsMade += 1
        UserDefaults.standard.set(redemptionsMade, forKey: redemptionsKey)
        PortfolioService.shared.mutateUser {
            $0.reelCoins += ReferralService.bonusPerSide
        }
    }

    static func generateCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789") // omit look-alikes
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
