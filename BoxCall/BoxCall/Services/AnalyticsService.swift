import Foundation

/// One-line-per-event analytics wrapper. Ships two sinks:
///   - `ConsoleAnalyticsSink` — always on in Debug for developer sanity
///   - `BoxCallBackendSink` — POSTs to api.boxcall.com/analytics/events.
///     Stubbed until the backend exists; fails silently and never blocks
///     the caller.
///
/// Events are anonymous (no PII). Sign-in status is tracked only as a
/// bool flag on each event.
///
/// Also installs a top-level uncaught-exception + signal handler that
/// logs a crash breadcrumb via the same pipeline before termination.
final class AnalyticsService {
    static let shared = AnalyticsService()

    var sinks: [AnalyticsSink] = [ConsoleAnalyticsSink(), BoxCallBackendSink()]
    var isEnabled: Bool = true

    private init() {}

    // MARK: - Public API

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        let sample = AnalyticsSample(
            name: event.name,
            props: event.props,
            timestamp: Date(),
            signedIn: AuthService.shared.isSignedIn,
            membership: PortfolioService.shared.user.membership.rawValue
        )
        for sink in sinks { sink.record(sample) }
    }

    func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            AnalyticsService.shared.track(.appCrash(
                reason: exception.reason ?? "unknown",
                stack: exception.callStackSymbols.prefix(20).joined(separator: "\n")
            ))
        }
        // Also catch common signals (best-effort; real crash reporting
        // uses PLCrashReporter or Sentry). We MUST reset to the default
        // handler before re-raising, otherwise `raise(sig)` reruns our
        // own handler and infinite-loops until the process is killed
        // by the OS instead of dumping a clean crash report.
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig) { s in
                AnalyticsService.shared.track(.appSignal(name: name(for: s)))
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
}

private func name(for signal: Int32) -> String {
    switch signal {
    case SIGABRT: return "SIGABRT"
    case SIGSEGV: return "SIGSEGV"
    case SIGBUS:  return "SIGBUS"
    case SIGILL:  return "SIGILL"
    case SIGFPE:  return "SIGFPE"
    default:      return "SIG\(signal)"
    }
}

// MARK: - Event catalog

enum AnalyticsEvent {
    case appOpen
    case appCrash(reason: String, stack: String)
    case appSignal(name: String)
    case screen(_ name: String)
    case tradePlaced(movieId: String, side: String, strike: Double, qty: Int, cost: Double)
    case tradeClosed(movieId: String, pnl: Double)
    case postShared(movieId: String, hasOutcome: Bool)
    case postLiked(postId: String)
    case reviewPublished(movieId: String, rating: Int)
    case badgeUnlocked(id: String)
    case tierPromoted(to: String)
    case membershipPurchased(tier: String)
    case referralRedeemed(code: String)
    case reportSubmitted(kind: String, reason: String)
    case signIn(method: String)
    case signOut

    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .appCrash: return "app_crash"
        case .appSignal: return "app_signal"
        case .screen: return "screen_view"
        case .tradePlaced: return "trade_placed"
        case .tradeClosed: return "trade_closed"
        case .postShared: return "post_shared"
        case .postLiked: return "post_liked"
        case .reviewPublished: return "review_published"
        case .badgeUnlocked: return "badge_unlocked"
        case .tierPromoted: return "tier_promoted"
        case .membershipPurchased: return "membership_purchased"
        case .referralRedeemed: return "referral_redeemed"
        case .reportSubmitted: return "report_submitted"
        case .signIn: return "sign_in"
        case .signOut: return "sign_out"
        }
    }

    var props: [String: String] {
        switch self {
        case .appOpen, .signOut: return [:]
        case .appCrash(let reason, let stack):
            return ["reason": reason, "stack_head": String(stack.prefix(400))]
        case .appSignal(let name): return ["signal": name]
        case .screen(let name): return ["name": name]
        case .tradePlaced(let m, let s, let k, let q, let c):
            return ["movie_id": m, "side": s, "strike": "\(k)", "qty": "\(q)", "cost": String(format: "%.2f", c)]
        case .tradeClosed(let m, let pnl):
            return ["movie_id": m, "pnl": String(format: "%.2f", pnl)]
        case .postShared(let m, let outcome):
            return ["movie_id": m, "has_outcome": outcome ? "1" : "0"]
        case .postLiked(let id): return ["post_id": id]
        case .reviewPublished(let m, let r):
            return ["movie_id": m, "rating": "\(r)"]
        case .badgeUnlocked(let id): return ["badge_id": id]
        case .tierPromoted(let t): return ["tier": t]
        case .membershipPurchased(let t): return ["tier": t]
        case .referralRedeemed(let c): return ["code": c]
        case .reportSubmitted(let kind, let reason):
            return ["kind": kind, "reason": reason]
        case .signIn(let m): return ["method": m]
        }
    }
}

// MARK: - Sample + sinks

struct AnalyticsSample {
    let name: String
    let props: [String: String]
    let timestamp: Date
    let signedIn: Bool
    let membership: String
}

protocol AnalyticsSink { func record(_ sample: AnalyticsSample) }

final class ConsoleAnalyticsSink: AnalyticsSink {
    func record(_ s: AnalyticsSample) {
        #if DEBUG
        let pairs = s.props.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("📊 \(s.name) | \(pairs) | signedIn=\(s.signedIn) tier=\(s.membership)")
        #endif
    }
}

/// Stub HTTP sink. Fails silently when the backend isn't reachable so
/// the app never blocks on analytics.
final class BoxCallBackendSink: AnalyticsSink {
    let endpoint: URL
    let session: URLSession
    init(endpoint: URL = URL(string: "https://api.boxcall.com/analytics/events")!,
         session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }
    func record(_ s: AnalyticsSample) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "name": s.name,
            "ts": ISO8601DateFormatter().string(from: s.timestamp),
            "signed_in": s.signedIn,
            "membership": s.membership
        ]
        payload["props"] = s.props
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        session.dataTask(with: req) { _, _, _ in }.resume()
    }
}
