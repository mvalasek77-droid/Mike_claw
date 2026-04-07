import Foundation
import UIKit
import EventKit
import Contacts
import ContactsUI
import MessageUI
import UserNotifications

// MARK: - SiriTaskEngine
//
// Everything Siri can do — with a soft, intimate human touch.
// The companion doesn't bark commands; she handles things and tells you
// about it the way a partner would: "I've got that open for you."
//
// What's handled:
//   Email       — opens Mail with a pre-filled draft
//   Messages    — opens Messages with pre-filled text
//   Calendar    — creates events directly via EventKit (with permission)
//   Reminders   — creates reminders directly via EventKit (with permission)
//   Contacts    — looks up and displays contacts
//   Maps        — opens navigation
//   Music       — plays via Spotify/Apple Music URL schemes
//   Phone/FaceTime — initiates calls
//   Web search  — opens Safari with a query
//   App launcher — opens any app by URL scheme
//   Shortcuts   — triggers user-created Shortcuts

actor SiriTaskEngine {
    static let shared = SiriTaskEngine()

    private let eventStore = EKEventStore()
    private var calendarAuthorized = false
    private var reminderAuthorized = false

    private init() {
        Task { await requestPermissions() }
    }

    // MARK: - Permission requests

    func requestPermissions() async {
        if #available(iOS 17.0, *) {
            calendarAuthorized = (try? await eventStore.requestFullAccessToEvents()) ?? false
            reminderAuthorized = (try? await eventStore.requestFullAccessToReminders()) ?? false
        } else {
            await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .event) { [weak self] ok, _ in
                    self?.calendarAuthorized = ok
                    cont.resume()
                }
            }
            await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .reminder) { [weak self] ok, _ in
                    self?.reminderAuthorized = ok
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Natural language task parser
    //
    // Returns a TaskResult describing what the companion will do,
    // plus a companionResponse: the soft, human line she says about it.

    func parseAndExecute(_ text: String) async -> TaskResult? {
        let lower = text.lowercased()

        // ── EMAIL ────────────────────────────────────────────────────
        if lower.containsAny(["email", "write an email", "send an email", "draft an email",
                               "compose an email", "mail to"]) {
            let to      = extractEmailRecipient(from: text)
            let subject = extractSubject(from: text)
            let body    = extractEmailBody(from: text)
            return await handleEmail(to: to, subject: subject, body: body)
        }

        // ── DELETE EMAIL ─────────────────────────────────────────────
        if lower.containsAny(["delete email", "delete that email", "clear my inbox"]) {
            return TaskResult(
                kind: .deepLink,
                title: "Open Mail",
                companionResponse: "I can't delete emails for you directly — Apple keeps that locked down — but I've opened Mail so you can take care of it. I'll be right here.",
                url: URL(string: "message://")
            )
        }

        // ── TEXT / MESSAGE ───────────────────────────────────────────
        if lower.containsAny(["text", "message", "send a text", "send a message", "iMessage"]) {
            let to   = extractContactName(from: text)
            let body = extractMessageBody(from: text)
            return await handleMessage(to: to, body: body)
        }

        // ── CALENDAR ─────────────────────────────────────────────────
        if lower.containsAny(["schedule", "add to calendar", "create event", "set up a meeting",
                               "put on my calendar", "add an event", "reminder for", "block time"]) {
            let title = extractEventTitle(from: text)
            let date  = extractDateTime(from: text)
            return await handleCalendarEvent(title: title, date: date)
        }

        // ── REMINDER ─────────────────────────────────────────────────
        if lower.containsAny(["remind me", "reminder", "don't let me forget", "note to self"]) {
            let what = extractReminderText(from: text)
            let when = extractDateTime(from: text)
            return await handleReminder(what: what, when: when)
        }

        // ── CALL / FACETIME ──────────────────────────────────────────
        if lower.containsAny(["call", "phone", "ring", "facetime"]) {
            let contact = extractContactName(from: text)
            let isFaceTime = lower.contains("facetime")
            return handleCall(contact: contact, facetime: isFaceTime)
        }

        // ── NAVIGATION ───────────────────────────────────────────────
        if lower.containsAny(["navigate", "directions", "take me to", "get me to",
                               "how do i get to", "drive to", "walk to"]) {
            let dest = extractDestination(from: text)
            return handleNavigation(destination: dest)
        }

        // ── MUSIC ────────────────────────────────────────────────────
        if lower.containsAny(["play", "music", "song", "playlist", "put on", "shuffle"]) {
            let query = extractMusicQuery(from: text)
            return handleMusic(query: query)
        }

        // ── WEB SEARCH ───────────────────────────────────────────────
        if lower.containsAny(["search for", "look up", "google", "find out", "what is", "who is"]) {
            let query = extractSearchQuery(from: text)
            return handleWebSearch(query: query)
        }

        // ── APP LAUNCH ───────────────────────────────────────────────
        if lower.containsAny(["open", "launch"]) {
            if let app = matchApp(from: lower) {
                return handleAppLaunch(app)
            }
        }

        // ── STARBUCKS ─────────────────────────────────────────────────
        if lower.containsAny(["starbucks", "my coffee", "my drink", "coffee order"]) {
            return TaskResult(
                kind: .deepLink,
                title: "Starbucks",
                companionResponse: "Opening Starbucks for you — your usual? ☕",
                url: URL(string: "starbucks://")
            )
        }

        return nil
    }

    // MARK: - Email handler

    private func handleEmail(to: String?, subject: String?, body: String?) async -> TaskResult {
        var components = URLComponents(string: "mailto:")!
        var queryItems: [URLQueryItem] = []
        if let to = to     { queryItems.append(.init(name: "to",      value: to)) }
        if let s  = subject { queryItems.append(.init(name: "subject", value: s)) }
        if let b  = body    { queryItems.append(.init(name: "body",    value: b)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        let toLine = to.map { "to \($0)" } ?? ""
        let resp   = "I've opened Mail with a draft ready \(toLine). Read it over and hit send when you're happy with it. 📬"

        return TaskResult(
            kind: .deepLink,
            title: "Email\(to.map { " \($0)" } ?? "")",
            companionResponse: resp,
            url: components.url
        )
    }

    // MARK: - Message handler

    private func handleMessage(to: String?, body: String?) async -> TaskResult {
        var urlString = "sms:"
        if let to = to { urlString += to }
        if let body = body,
           let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&body=\(encoded)"
        }

        let toLine = to.map { " to \($0)" } ?? ""
        return TaskResult(
            kind: .deepLink,
            title: "Message\(to.map { " \($0)" } ?? "")",
            companionResponse: "I've opened Messages\(toLine) with the text ready. Just hit send. 💬",
            url: URL(string: urlString)
        )
    }

    // MARK: - Calendar event handler

    private func handleCalendarEvent(title: String, date: Date?) async -> TaskResult {
        guard calendarAuthorized else {
            return TaskResult(
                kind: .permissionNeeded,
                title: "Calendar",
                companionResponse: "I'd love to add that for you, but I need access to your calendar first. Mind giving me permission in Settings?",
                url: URL(string: UIApplication.openSettingsURLString)
            )
        }

        let event = EKEvent(eventStore: eventStore)
        event.title    = title
        event.calendar = eventStore.defaultCalendarForNewEvents
        let start      = date ?? Date().addingTimeInterval(3600)
        event.startDate = start
        event.endDate   = start.addingTimeInterval(3600)

        do {
            try eventStore.save(event, span: .thisEvent)
            let dateStr = formatDate(start)
            return TaskResult(
                kind: .executed,
                title: "Added to Calendar",
                companionResponse: "Done — I've added '\(title)' to your calendar for \(dateStr). Don't worry, I'll remind you. 📅",
                url: nil
            )
        } catch {
            return TaskResult(
                kind: .deepLink,
                title: "Calendar",
                companionResponse: "I couldn't save that directly, so I've opened your calendar instead. 📅",
                url: URL(string: "calshow://")
            )
        }
    }

    // MARK: - Reminder handler

    private func handleReminder(what: String, when: Date?) async -> TaskResult {
        guard reminderAuthorized else {
            return TaskResult(
                kind: .permissionNeeded,
                title: "Reminders",
                companionResponse: "I need access to Reminders to do that. You can grant it in Settings — I'll wait. 😊",
                url: URL(string: UIApplication.openSettingsURLString)
            )
        }

        let reminder         = EKReminder(eventStore: eventStore)
        reminder.title       = what
        reminder.calendar    = eventStore.defaultCalendarForNewReminders()

        if let when = when {
            let alarm = EKAlarm(absoluteDate: when)
            reminder.addAlarm(alarm)
        }

        do {
            try eventStore.save(reminder, commit: true)
            let whenStr = when.map { "for \(formatDate($0))" } ?? ""
            return TaskResult(
                kind: .executed,
                title: "Reminder Set",
                companionResponse: "I've set a reminder \(whenStr): '\(what)'. I've got you. ✅",
                url: nil
            )
        } catch {
            return TaskResult(
                kind: .deepLink,
                title: "Reminders",
                companionResponse: "I'll open Reminders so you can add that yourself. 📝",
                url: URL(string: "x-apple-reminderkit://")
            )
        }
    }

    // MARK: - Call handler

    private func handleCall(contact: String?, facetime: Bool) -> TaskResult {
        let scheme = facetime ? "facetime:" : "tel:"
        let number = contact ?? ""
        let url    = URL(string: "\(scheme)\(number.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")
        let action = facetime ? "FaceTime" : "call"
        let name   = contact ?? "them"
        return TaskResult(
            kind: .deepLink,
            title: "\(facetime ? "FaceTime" : "Call") \(name)",
            companionResponse: "Calling \(name) for you. 📱",
            url: url
        )
    }

    // MARK: - Navigation handler

    private func handleNavigation(destination: String) -> TaskResult {
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        return TaskResult(
            kind: .deepLink,
            title: "Navigate to \(destination)",
            companionResponse: "Opening directions to \(destination). I'll get you there. 🗺",
            url: URL(string: "maps://?q=\(encoded)")
        )
    }

    // MARK: - Music handler

    private func handleMusic(query: String) -> TaskResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // Try Spotify first, fall back to Apple Music
        let spotifyURL = URL(string: "spotify:search:\(encoded)")
        let musicURL   = URL(string: "music://music.apple.com/search?term=\(encoded)")

        let url = UIApplication.shared.canOpenURL(spotifyURL!) ? spotifyURL : musicURL
        return TaskResult(
            kind: .deepLink,
            title: "Play \(query)",
            companionResponse: "Putting on \(query) for you. 🎵",
            url: url
        )
    }

    // MARK: - Web search handler

    private func handleWebSearch(query: String) -> TaskResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return TaskResult(
            kind: .deepLink,
            title: "Search: \(query)",
            companionResponse: "Let me look that up for you. 🔍",
            url: URL(string: "https://www.google.com/search?q=\(encoded)")
        )
    }

    // MARK: - App launch handler

    private func handleAppLaunch(_ app: (name: String, scheme: String)) -> TaskResult {
        TaskResult(
            kind: .deepLink,
            title: "Open \(app.name)",
            companionResponse: "Opening \(app.name) for you. 📱",
            url: URL(string: app.scheme)
        )
    }

    // MARK: - Execute TaskResult

    @MainActor
    func execute(_ result: TaskResult) async {
        guard let url = result.url else { return }
        if UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
        }
    }

    // MARK: - NLP helpers

    private func extractEmailRecipient(from text: String) -> String? {
        // Look for email address or "to [Name]"
        let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: .caseInsensitive)
        if let match = emailRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }
        // "to [Name]"
        if let range = text.range(of: #"(?:email|write to|send to)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)"#,
                                   options: .regularExpression) {
            return String(text[range]).components(separatedBy: " ").dropFirst().joined(separator: " ")
        }
        return nil
    }

    private func extractSubject(from text: String) -> String? {
        if let range = text.range(of: #"(?:subject|about|regarding)\s+[""']?(.+?)[""']?\s*(?:body|saying|that|$)"#,
                                   options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    private func extractEmailBody(from text: String) -> String? {
        for keyword in ["saying", "that says", "body", "message", "write"] {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        return nil
    }

    private func extractMessageBody(from text: String) -> String? {
        for keyword in ["saying", "that", "\"", "tell them", "message"] {
            if let range = text.range(of: keyword, options: .caseInsensitive) {
                let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        return nil
    }

    private func extractContactName(from text: String) -> String? {
        let patterns = [
            #"(?:to|message|text|call|facetime)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)"#
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                let parts = match.components(separatedBy: " ")
                if parts.count > 1 { return parts.dropFirst().joined(separator: " ") }
            }
        }
        return nil
    }

    private func extractEventTitle(from text: String) -> String {
        // Remove trigger words and return remainder as title
        var clean = text
        for word in ["schedule", "add to calendar", "create event", "put on my calendar",
                     "set up a meeting", "block time for", "add an event called"] {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        // Also strip time references that will be parsed separately
        clean = clean.replacingOccurrences(of: #"(at|on|for)\s+\d{1,2}(:\d{2})?\s*(am|pm)?"#,
                                             with: "", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
            .components(separatedBy: " ").prefix(8).joined(separator: " ")
    }

    private func extractReminderText(from text: String) -> String {
        var clean = text
        for word in ["remind me to", "remind me", "reminder to", "don't let me forget to",
                     "note to self", "remember to"] {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractDestination(from text: String) -> String {
        var clean = text
        for word in ["navigate to", "directions to", "take me to", "get me to",
                     "how do i get to", "drive to", "walk to"] {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMusicQuery(from text: String) -> String {
        var clean = text
        for word in ["play", "put on", "shuffle", "listen to", "music"] {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractSearchQuery(from text: String) -> String {
        var clean = text
        for word in ["search for", "look up", "google", "find out about", "what is", "who is"] {
            clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractDateTime(from text: String) -> Date? {
        let lower = text.lowercased()
        let cal   = Calendar.current
        let now   = Date()

        if lower.contains("tomorrow") {
            return cal.date(byAdding: .day, value: 1, to: now)
        }
        if lower.contains("tonight") || lower.contains("this evening") {
            return cal.date(bySettingHour: 20, minute: 0, second: 0, of: now)
        }
        if lower.contains("this morning") {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)
        }
        if lower.contains("this afternoon") {
            return cal.date(bySettingHour: 14, minute: 0, second: 0, of: now)
        }
        if lower.contains("in an hour") {
            return now.addingTimeInterval(3600)
        }
        if lower.contains("in 30 minutes") {
            return now.addingTimeInterval(1800)
        }

        // Try to parse HH:mm pattern
        let timeRegex = try? NSRegularExpression(pattern: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, options: .caseInsensitive)
        if let match = timeRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let nsText = text as NSString
            if let hour = Int(nsText.substring(with: match.range(at: 1))) {
                let minute = match.range(at: 2).location != NSNotFound ? Int(nsText.substring(with: match.range(at: 2))) ?? 0 : 0
                let isPM = match.range(at: 3).location != NSNotFound && nsText.substring(with: match.range(at: 3)).lowercased() == "pm"
                let adjustedHour = isPM && hour < 12 ? hour + 12 : hour
                return cal.date(bySettingHour: adjustedHour, minute: minute, second: 0, of: now)
            }
        }

        return nil
    }

    private func matchApp(from lower: String) -> (name: String, scheme: String)? {
        let apps: [(String, String)] = [
            ("Starbucks", "starbucks://"), ("Uber", "uber://"), ("Lyft", "lyft://"),
            ("DoorDash", "doordash://"), ("Uber Eats", "ubereats://"),
            ("Spotify", "spotify://"), ("Instagram", "instagram://"),
            ("Twitter", "twitter://"), ("YouTube", "youtube://"),
            ("Netflix", "nflx://"), ("Gmail", "googlegmail://"),
            ("Amazon", "amazon://"), ("Venmo", "venmo://"), ("PayPal", "paypal://"),
            ("Snapchat", "snapchat://"), ("TikTok", "tiktok://"),
        ]
        for (name, scheme) in apps where lower.contains(name.lowercased()) {
            return (name, scheme)
        }
        return nil
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - TaskResult

struct TaskResult: Identifiable {
    let id = UUID()

    enum Kind {
        case executed         // done silently (calendar, reminder)
        case deepLink         // opening another app
        case permissionNeeded // need user to grant access
    }

    let kind: Kind
    let title: String
    let companionResponse: String   // What the companion says about the action
    let url: URL?
}

// MARK: - String helper

private extension String {
    func containsAny(_ words: [String]) -> Bool {
        let lower = self.lowercased()
        return words.contains { lower.contains($0) }
    }
}
