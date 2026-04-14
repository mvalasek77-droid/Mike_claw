import Foundation
import AVFoundation
import UIKit

// MARK: - StressLearningEngine
//
// The emotional intelligence layer. Monitors the user's environment and daily
// patterns to learn what they do when stressed — then gently offers that relief
// before the user has to ask.
//
// Philosophy:
//   • Observe quietly. Learn patterns. Never assume.
//   • Offer, don't force. One gentle ask, then back off.
//   • After enough acceptance, act first — then check in.
//   • Always learning: every yes or no makes the engine smarter.
//
// Stress signals it monitors:
//   • Ambient noise level (RMS via microphone)
//   • Time of day / day of week patterns
//   • Topics HerMode has heard recently
//   • Historical stress patterns the user has shown before
//
// Relief behaviours it learns:
//   • Streaming apps  (Netflix, YouTube)
//   • Food ordering   (Chipotle, UberEats, DoorDash)
//   • Music / audio   (Spotify, Apple Music, a specific playlist)
//   • Movement        (walking, gym)
//   • Breathing       (guided meditation)
//   • Social          (call someone the user listed)

// MARK: - Data models

struct StressReliefAction: Codable, Identifiable {
    let id: String
    var label: String
    var deepLink: String?
    var category: Category
    var acceptCount: Int   = 0
    var rejectCount: Int   = 0
    var lastOffered: Date  = .distantPast
    let autoThreshold: Int = 5        // accepted this many times → act automatically

    enum Category: String, Codable {
        case streaming, food, music, movement, breathing, social, custom
    }

    var acceptanceRate: Double {
        let total = acceptCount + rejectCount
        return total > 0 ? Double(acceptCount) / Double(total) : 0.5
    }

    /// If acceptance rate is high and user has accepted enough times,
    /// act first (then ask "was that ok?") rather than asking first.
    var shouldAutoAct: Bool {
        acceptCount >= autoThreshold && acceptanceRate >= 0.70
    }
}

struct StressOffer: Identifiable {
    let id           = UUID()
    let message:      String
    let action:       StressReliefAction
    let context:      String     // human-readable reason: "sounds like a rough commute"
}

// MARK: - Engine

@MainActor
final class StressLearningEngine: ObservableObject {

    static let shared = StressLearningEngine()

    // MARK: Published
    @Published var stressLevel:   Double      = 0.0    // 0 – 1
    @Published var currentOffer:  StressOffer? = nil
    @Published var isMonitoring:  Bool         = false

    // MARK: Private — relief catalogue
    private var catalogue: [StressReliefAction] = []

    // MARK: Private — timing gates
    private var lastOfferAt:      Date = .distantPast
    private let offerCooldown:    TimeInterval = 1800   // 30 min between offers
    private var evaluationTimer:  Timer?

    // MARK: Private — ambient noise measurement
    private let audioEngine      = AVAudioEngine()
    private var noiseSamples:    [Float] = []
    private var tapInstalled:    Bool = false

    private let defaults = UserDefaults.standard

    // MARK: - Init

    private init() {
        loadCatalogue()
        if catalogue.isEmpty { seedDefaultCatalogue() }
    }

    // MARK: - Monitoring lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        installNoiseTap()
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.evaluate() }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        removeNoiseTap()
        evaluationTimer?.invalidate()
        evaluationTimer = nil
    }

    // MARK: - Noise tap (ambient stress measurement)

    private func installNoiseTap() {
        guard !tapInstalled else { return }
        let node   = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            guard let chan = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var rms: Float = 0
            for i in 0..<n { rms += chan[i] * chan[i] }
            rms = sqrt(rms / Float(n))
            Task { @MainActor in
                self?.noiseSamples.append(rms)
                if (self?.noiseSamples.count ?? 0) > 90 { self?.noiseSamples.removeFirst() }
            }
        }
        tapInstalled = true
        audioEngine.prepare()
        try? audioEngine.start()
    }

    private func removeNoiseTap() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        tapInstalled = false
    }

    private var averageNoise: Double {
        guard !noiseSamples.isEmpty else { return 0 }
        let avg = noiseSamples.reduce(0, +) / Float(noiseSamples.count)
        // Normalize: typical quiet room ≈ 0.01 RMS → map to 0-1 range
        return Double(min(avg * 25.0, 1.0))
    }

    // MARK: - Stress evaluation (runs every minute)

    private func evaluate() async {
        var score = 0.0

        // ── Signal 1: ambient noise ──────────────────────────────────
        score += averageNoise * 0.28

        // ── Signal 2: time-of-day stress windows ─────────────────────
        let now      = Date()
        let hour     = Calendar.current.component(.hour, from: now)
        let weekday  = Calendar.current.component(.weekday, from: now)

        if (7...9).contains(hour) || (17...19).contains(hour) { score += 0.22 }  // commute
        if hour >= 22 || hour <= 5 { score += 0.18 }                             // late night
        if weekday == 2 { score += 0.14 }   // Monday
        if weekday == 6 { score += 0.10 }   // Friday (end-of-week burnout)

        // ── Signal 3: HerMode emotional topic detection ───────────────
        if let topic = HerModeEngine.shared.lastHeardTopic {
            let stressTopics = ["feelings", "work", "health", "loss", "relationships", "money"]
            if stressTopics.contains(topic) { score += 0.30 }
        }

        // ── Signal 4: historical pattern at this time ─────────────────
        score += historicalScore(hour: hour, weekday: weekday) * 0.18

        stressLevel = min(score, 1.0)

        // Only offer if stress meaningfully detected
        if stressLevel >= 0.48 {
            await considerOffer(hour: hour, weekday: weekday)
        }
    }

    // MARK: - Pattern history

    private func historicalScore(hour: Int, weekday: Int) -> Double {
        defaults.double(forKey: "stress.hist.\(weekday).\(hour)")
    }

    private func recordStressEvent(hour: Int, weekday: Int) {
        let key = "stress.hist.\(weekday).\(hour)"
        let v   = defaults.double(forKey: key)
        defaults.set(min(v * 0.80 + 0.20, 1.0), forKey: key)   // exponential moving avg
    }

    // MARK: - Offer logic

    private func considerOffer(hour: Int, weekday: Int) async {
        guard Date().timeIntervalSince(lastOfferAt) > offerCooldown else { return }
        guard !CompanionVoiceEngine.shared.isSpeaking else { return }
        guard currentOffer == nil else { return }

        // Pick best candidate — highest acceptance rate, not offered recently
        let candidate = catalogue
            .filter { Date().timeIntervalSince($0.lastOffered) > 3600 }
            .sorted { $0.acceptanceRate > $1.acceptanceRate }
            .first

        guard var action = candidate else { return }

        let companion = loadCompanion()
        let context   = contextDescription(hour: hour)
        let message   = buildMessage(action: action, context: context, companion: companion)

        lastOfferAt = Date()
        recordStressEvent(hour: hour, weekday: weekday)

        // Update last-offered timestamp in catalogue
        if let idx = catalogue.firstIndex(where: { $0.id == action.id }) {
            catalogue[idx].lastOffered = Date()
            action = catalogue[idx]
        }

        if action.shouldAutoAct {
            // Learned behaviour: act first, verify after
            openDeepLink(action.deepLink)
            let autoMsg = "I went ahead and \(action.label.lowercased()) — I thought it might help. Was that ok? If you'd rather I ask first next time, just let me know."
            CompanionVoiceEngine.shared.speak(autoMsg, character: companion.voiceCharacter)
        } else {
            // First-time or uncertain: ask
            currentOffer = StressOffer(message: message, action: action, context: context)
            CompanionVoiceEngine.shared.speak(message, character: companion.voiceCharacter)
        }

        saveCatalogue()
    }

    // MARK: - Message building

    private func contextDescription(hour: Int) -> String {
        switch hour {
        case 7...9:   return "morning rush"
        case 12...13: return "lunch hour"
        case 17...19: return "end of the day"
        case 21...23: return "late night wind-down"
        default:      return "right now"
        }
    }

    private func buildMessage(action: StressReliefAction,
                               context: String,
                               companion: CompanionPersonality) -> String {
        let openers: [String]
        if stressLevel > 0.75 {
            openers = [
                "Hey… it sounds like a lot is happening. ",
                "I'm picking up on some tension. ",
                "Hey — I just want to check in. "
            ]
        } else {
            openers = [
                "Hey… ",
                "I noticed the \(context). ",
                "Just checking in — "
            ]
        }

        let offers: [String] = [
            "Want me to \(action.label.lowercased())?",
            "Would it help if I \(action.label.lowercased())?",
            "I could \(action.label.lowercased()), if you want.",
            "No pressure — but I could \(action.label.lowercased()) if that sounds good."
        ]

        return (openers.randomElement() ?? "") + (offers.randomElement() ?? "")
    }

    // MARK: - User response

    func acceptOffer() {
        guard let offer = currentOffer else { return }
        if let i = catalogue.firstIndex(where: { $0.id == offer.action.id }) {
            catalogue[i].acceptCount += 1
        }
        openDeepLink(offer.action.deepLink)
        saveCatalogue()
        currentOffer = nil
    }

    func rejectOffer() {
        guard let offer = currentOffer else { return }
        if let i = catalogue.firstIndex(where: { $0.id == offer.action.id }) {
            catalogue[i].rejectCount += 1
        }
        saveCatalogue()
        currentOffer = nil
    }

    // MARK: - Teach the engine a new relief action

    /// Call this when the user mentions something they do when stressed
    /// e.g. "I always watch Narcos when I'm stressed"
    func learnAction(label: String, deepLink: String?, category: StressReliefAction.Category) {
        let existing = catalogue.first { $0.label.lowercased() == label.lowercased() }
        guard existing == nil else { return }   // already known
        let action = StressReliefAction(
            id: UUID().uuidString, label: label,
            deepLink: deepLink, category: category
        )
        catalogue.append(action)
        saveCatalogue()
    }

    // MARK: - Deep-link launcher

    private func openDeepLink(_ urlString: String?) {
        guard let str = urlString,
              let url = URL(string: str),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Default catalogue

    private func seedDefaultCatalogue() {
        catalogue = [
            StressReliefAction(id: "netflix",      label: "Open Netflix",
                               deepLink: "nflx://", category: .streaming),
            StressReliefAction(id: "youtube",      label: "Open YouTube",
                               deepLink: "youtube://", category: .streaming),
            StressReliefAction(id: "spotify",      label: "Play something calming on Spotify",
                               deepLink: "spotify:", category: .music),
            StressReliefAction(id: "apple_music",  label: "Play music",
                               deepLink: "music://", category: .music),
            StressReliefAction(id: "chipotle",     label: "Order from Chipotle",
                               deepLink: "chipotle://", category: .food),
            StressReliefAction(id: "doordash",     label: "Order food delivery",
                               deepLink: "doordash://", category: .food),
            StressReliefAction(id: "walk",         label: "Head out for a quick walk",
                               deepLink: nil, category: .movement),
            StressReliefAction(id: "breathe",      label: "Try a 2-minute breathing exercise",
                               deepLink: nil, category: .breathing),
        ]
        saveCatalogue()
    }

    // MARK: - Persistence

    private func loadCatalogue() {
        guard let data    = defaults.data(forKey: "stress.catalogue"),
              let decoded = try? JSONDecoder().decode([StressReliefAction].self, from: data)
        else { return }
        catalogue = decoded
    }

    private func saveCatalogue() {
        if let data = try? JSONEncoder().encode(catalogue) {
            defaults.set(data, forKey: "stress.catalogue")
        }
    }

    private func loadCompanion() -> CompanionPersonality {
        let id = defaults.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }
}
