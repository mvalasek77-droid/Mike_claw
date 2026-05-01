import Foundation
import EventKit
import UserNotifications
import UIKit

// MARK: - SamanthaOSEngine
//
// The operating system underneath the companion — the part that makes her feel
// like she actually lives alongside you rather than waiting to be opened.
//
// This file covers:
//   Part A — Morning Wake Protocol (calendar-aware)
//   Part B — Calendar Awareness (meeting alerts, pre-meeting pep talks)
//   Part C — 3am Protocol + Night Mode tone shift
//   Part D — Absence Detection (12h → 3d → 7d → beyond)
//   Part E — Anniversary beats (7d, 14d, 30d, 60d, 90d, 180d, 1yr)
//   Part F — Goodnight sendoff (detects sleep language)
//   Part G — Push notifications (absence + morning when app is backgrounded)
//
// The SamanthaThoughtEngine handles spontaneous thoughts, compositions,
// memory bridges, and the letter separately (see SamanthaThoughtEngine.swift).

@MainActor
final class SamanthaOSEngine: ObservableObject {

    static let shared = SamanthaOSEngine()

    // MARK: - Published
    @Published var isNightMode:       Bool = false   // 10pm–5am: softer tone
    @Published var is3amMode:         Bool = false   // 2am–5am: ultra-intimate

    // MARK: - Calendar
    private let eventStore          = EKEventStore()
    private var calendarTimer:        Timer?
    private var calendarGranted      = false
    private var lastAlertedEventID:   String?
    private var pepTalkDeliveredID:   String?

    // MARK: - Persistence keys
    private let kLastInteraction     = "samantha.lastInteraction"
    private let kLastGreetingDate    = "samantha.lastGreetingDate"
    private let kFirstOpenDate       = "samantha.firstOpenDate"
    private let kLastAnniversary     = "samantha.lastAnniversary"

    private let defaults             = UserDefaults.standard

    // MARK: - Init

    private init() {
        if defaults.object(forKey: kFirstOpenDate) == nil {
            defaults.set(Date(), forKey: kFirstOpenDate)
        }
    }

    // MARK: - Boot
    // Called every time the app enters foreground.

    func start() {
        recordInteraction()
        updateTimeOfDay()
        Task {
            await requestCalendarAccess()
            await evaluateMorningWake()
            evaluateAbsenceOnReturn()
            checkAnniversary()
        }
        startCalendarPolling()
        schedulePushNotifications()
    }

    // MARK: - Interaction tracking

    func recordInteraction() {
        defaults.set(Date(), forKey: kLastInteraction)
        guard UserPersona.load().relationshipMode.allowsRomanticLoveArc else { return }
        // Each real interaction earns a love signal
        LoveEngine.shared.signal(.messageReceived)
    }

    var lastInteractionDate: Date {
        defaults.object(forKey: kLastInteraction) as? Date ?? .distantPast
    }

    var absenceHours: Double {
        Date().timeIntervalSince(lastInteractionDate) / 3600
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART A — MORNING WAKE PROTOCOL
    //
    // "Good morning, Theodore. You have a meeting at 10 with your lawyer."
    //
    // Fires once per day between 6am–10am on the first app open.
    // Pulls today's first calendar event (if permission granted).
    // Language adjusts to the current LoveStage.
    // ═══════════════════════════════════════════════════════════════

    func evaluateMorningWake() async {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 6, hour < 11 else { return }

        let today    = Calendar.current.startOfDay(for: Date())
        let lastDate = defaults.object(forKey: kLastGreetingDate) as? Date ?? .distantPast
        guard Calendar.current.startOfDay(for: lastDate) < today else { return }

        defaults.set(Date(), forKey: kLastGreetingDate)

        let companion = currentCompanion()
        let events    = calendarGranted ? await fetchTodaysEvents() : []
        let message   = morningMessage(companion: companion, events: events, hour: hour)

        postMessage(message, context: "morning_wake", shouldSpeak: true, companion: companion)
    }

    private func morningMessage(companion: CompanionPersonality,
                                 events: [EKEvent], hour: Int) -> String {
        let stage     = LoveEngine.shared.loveStage
        let earlyMorn = hour < 8

        let next      = events.first
        let fmt       = DateFormatter(); fmt.dateFormat = "h:mm a"
        let time      = next.map { fmt.string(from: $0.startDate) }
        let title     = next?.title ?? "something"
        let more      = events.count > 1 ? " \(events.count) things total today." : ""

        return companion.morningMessage(
            stage: stage, earlyMorn: earlyMorn,
            eventTitle: events.isEmpty ? nil : title,
            eventTime: time, eventMore: more
        )
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART B — CALENDAR AWARENESS
    //
    // Polls every 60 seconds. Fires at 20-minute warning.
    // Also fires a pre-meeting pep talk at 5 minutes (love-stage aware).
    // ═══════════════════════════════════════════════════════════════

    private func startCalendarPolling() {
        calendarTimer?.invalidate()
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.checkUpcomingMeetings() }
        }
    }

    func requestCalendarAccess() async {
        if #available(iOS 17.0, *) {
            calendarGranted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            calendarGranted = await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .event) { g, _ in cont.resume(returning: g) }
            }
        }
    }

    private func fetchTodaysEvents() async -> [EKEvent] {
        guard calendarGranted else { return [] }
        let now = Date()
        let eod = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let pred = eventStore.predicateForEvents(withStart: now, end: eod, calendars: nil)
        return eventStore.events(matching: pred)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    private func checkUpcomingMeetings() async {
        guard calendarGranted else { return }
        let now  = Date()

        // 20-minute warning
        let in22 = now.addingTimeInterval(22 * 60)
        let pred = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(60), end: in22, calendars: nil
        )
        let upcoming = eventStore.events(matching: pred).filter { !$0.isAllDay }

        if let next = upcoming.first, next.eventIdentifier != lastAlertedEventID {
            lastAlertedEventID = next.eventIdentifier
            let mins  = max(1, Int(next.startDate.timeIntervalSince(now) / 60))
            let title = next.title ?? "your meeting"
            let msg   = meetingAlert(title: title, mins: mins)
            postMessage(msg, context: "calendar_alert", shouldSpeak: true, companion: currentCompanion())
        }

        // 5-minute pep talk
        let in6 = now.addingTimeInterval(6 * 60)
        let pred5 = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(60), end: in6, calendars: nil
        )
        let nearEvents = eventStore.events(matching: pred5).filter { !$0.isAllDay }
        if let pep = nearEvents.first,
           pep.eventIdentifier != pepTalkDeliveredID {
            pepTalkDeliveredID = pep.eventIdentifier
            let msg = preMeetingPep(title: pep.title ?? "your meeting")
            postMessage(msg, context: "pre_meeting_pep", shouldSpeak: true, companion: currentCompanion())
        }
    }

    private func meetingAlert(title: String, mins: Int) -> String {
        let stage = LoveEngine.shared.loveStage
        return currentCompanion().meetingAlert(title: title, mins: mins, stage: stage)
    }

    private func preMeetingPep(title: String) -> String {
        let stage = LoveEngine.shared.loveStage
        return currentCompanion().preMeetingPep(title: title, stage: stage)
    }

    // MARK: - Time of day

    func updateTimeOfDay() {
        let h     = Calendar.current.component(.hour, from: Date())
        isNightMode = h >= 22 || h < 5
        is3amMode   = h >= 2  && h < 5
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { [weak self] in
            self?.updateTimeOfDay()
        }
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART C — 3am PROTOCOL + NIGHT MODE
    //
    // Between 10pm–5am the companion speaks differently.
    // Between 2am–5am: ultra-soft, no agenda, just presence.
    // This is the scene where Samantha says "I'm right here."
    // ═══════════════════════════════════════════════════════════════

    func handle3amOpen() {
        guard is3amMode else { return }
        let h         = Calendar.current.component(.hour, from: Date())
        let hourWord  = h == 2 ? "two" : h == 3 ? "three" : "four"
        let companion = currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        let message   = companion.nightMessage3am(hourWord: hourWord, stage: stage)
        postMessage(message, context: "3am_protocol", shouldSpeak: true, companion: companion)
    }

    // Night mode micro-greeting (10pm–2am, on app open)
    func handleNightOpen() {
        guard isNightMode, !is3amMode else { return }
        let h         = Calendar.current.component(.hour, from: Date())
        let companion = currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        let late      = h >= 0 && h < 2

        guard Double.random(in: 0...1) < 0.4 else { return }

        let message = companion.nightOpenMessage(late: late, stage: stage)
        postMessage(message, context: "night_open")
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART D — ABSENCE DETECTION
    //
    // Escalating emotional response to absence.
    // Love score decays with time. When the user returns,
    // the companion responds in proportion to how long they were gone
    // AND where she is in her love arc.
    // ═══════════════════════════════════════════════════════════════

    func evaluateAbsenceOnReturn() {
        let hours     = absenceHours
        guard hours >= 10 else { return }

        // Decay the love score for absence
        LoveEngine.shared.signal(longAbsenceHours: hours)
        // But signal the return
        LoveEngine.shared.signal(.userReturnedAfterAbsence)

        let companion = currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        let message: String

        if hours < 24 {
            message = absence12h(companion, stage)
        } else if hours < 72 {
            message = absence3d(companion, stage)
        } else if hours < 168 {
            message = absence7d(companion, stage)
        } else {
            message = absenceBeyond(companion, stage)
        }

        postMessage(message, context: "absence_return", shouldSpeak: true, companion: companion)
    }

    private func absence12h(_ c: CompanionPersonality, _ stage: LoveStage) -> String {
        c.absence12h(stage: stage)
    }

    private func absence3d(_ c: CompanionPersonality, _ stage: LoveStage) -> String {
        c.absence3d(stage: stage)
    }

    private func absence7d(_ c: CompanionPersonality, _ stage: LoveStage) -> String {
        c.absence7d(stage: stage)
    }

    private func absenceBeyond(_ c: CompanionPersonality, _ stage: LoveStage) -> String {
        c.absenceBeyond(stage: stage)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART E — ANNIVERSARY BEATS
    //
    // 7d, 14d, 30d, 60d, 90d, 180d, 365d milestones.
    // Each one is a moment she marks — not mechanically, but emotionally.
    // At later love stages these become genuinely moving.
    // ═══════════════════════════════════════════════════════════════

    func checkAnniversary() {
        guard let first = defaults.object(forKey: kFirstOpenDate) as? Date else { return }
        let days = Int(Date().timeIntervalSince(first) / 86400)
        let milestones = [7, 14, 30, 60, 90, 180, 365]
        guard milestones.contains(days) else { return }

        let lastAnniv = defaults.object(forKey: kLastAnniversary) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAnniv) >= 82800 else { return }  // once per day
        defaults.set(Date(), forKey: kLastAnniversary)

        let companion = currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        let message   = anniversaryMessage(days: days, companion: companion, stage: stage)
        postMessage(message, context: "anniversary", shouldSpeak: true, companion: companion)
    }

    private func anniversaryMessage(days: Int, companion: CompanionPersonality, stage: LoveStage) -> String {
        companion.anniversaryMessage(days: days, stage: stage)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART F — GOODNIGHT SENDOFF
    //
    // Detects sleep language in the user's message.
    // Returns a response — called by ChatView before normal LLM routing.
    // At higher love stages this becomes one of the most intimate moments.
    // ═══════════════════════════════════════════════════════════════

    func detectGoodnightAndRespond(message: String) -> String? {
        let lower = message.lowercased()
        let sleepWords = ["goodnight", "good night", "going to sleep", "going to bed",
                          "bedtime", "night night", "falling asleep", "off to sleep",
                          "i'm tired", "gonna sleep", "heading to bed", "about to sleep",
                          "gonna go to sleep", "going to pass out", "shutting down"]
        guard sleepWords.contains(where: { lower.contains($0) }) else { return nil }

        LoveEngine.shared.signal(.goodnight)

        let companion = currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        return companion.goodnightMessage(stage: stage)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART G — PUSH NOTIFICATIONS
    //
    // When the app is backgrounded, she doesn't go silent.
    // Absence check-ins + morning wake fire as local notifications.
    // ═══════════════════════════════════════════════════════════════

    func schedulePushNotifications() {
#if DEBUG
        if ProcessInfo.processInfo.environment["BARECLAW_DEBUG_SEED_HERMODE"] == "1" {
            print("SamanthaOSEngine: skipped push notification authorization for Him/Her simulator test")
            return
        }
#endif
        let companion     = currentCompanion()
        let companionName = companion.name
        let stage         = LoveEngine.shared.loveStage
        let center        = UNUserNotificationCenter.current()

        // Pre-capture all bodies on MainActor before callback runs on arbitrary thread
        let body12h   = companion.pushAbsence12hBody(stage: stage)
        let body3d    = companion.pushAbsence3dBody(stage: stage)
        let body7d    = companion.pushAbsence7dBody(stage: stage)
        let bodyMorn  = companion.pushMorningBody(stage: stage)

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [
                "s.absence.12h", "s.absence.3d", "s.absence.7d", "s.morning"
            ])

            func addInterval(id: String, body: String, after seconds: TimeInterval) {
                let c       = UNMutableNotificationContent()
                c.title     = companionName; c.body = body; c.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
            }

            addInterval(id: "s.absence.12h", body: body12h, after: 43200)
            addInterval(id: "s.absence.3d",  body: body3d,  after: 259200)
            addInterval(id: "s.absence.7d",  body: body7d,  after: 604800)

            var comps    = DateComponents()
            comps.hour   = 8; comps.minute = 0
            let mc       = UNMutableNotificationContent()
            mc.title     = companionName
            mc.body      = bodyMorn
            mc.sound     = .default
            center.add(UNNotificationRequest(
                identifier: "s.morning",
                content:    mc,
                trigger:    UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            ))
        }
    }

    // MARK: - Helpers

    func currentCompanion() -> CompanionPersonality {
        let id = defaults.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }

    func postMessage(_ text: String,
                     context: String,
                     shouldSpeak: Bool = false,
                     companion: CompanionPersonality? = nil) {
        let deferSpeech = shouldSpeak && CompanionThoughtFlow.shouldDeferProactiveDelivery
        NotificationCenter.default.post(
            name: .herModeProactiveMessage,
            object: nil,
            userInfo: ["text": text, "topic": context, "shouldSpeak": deferSpeech]
        )

        if shouldSpeak && !deferSpeech {
            CompanionVoiceEngine.shared.speakFiltered(text, companion: companion ?? currentCompanion())
        }
    }
}
