import Foundation
import EventKit
import UserNotifications

// MARK: - CompanionDataTracker
//
// An actor that observes the data sources the user has permitted (calendar,
// reminders) and fires emotionally intelligent companion push notifications
// at meaningful moments — before an interview, after a medical appointment,
// or a gentle nudge for an overdue reminder.
//
// Call `updatePermissions(_:persona:)` on every app launch and whenever the
// user toggles a permission toggle in Settings.

actor CompanionDataTracker {

    // MARK: - Singleton

    static let shared = CompanionDataTracker()

    // MARK: - Private state

    /// The most recently stored permissions snapshot. Every scan re-checks
    /// this before doing any work so a mid-flight permission revocation is
    /// respected without waiting for the next launch.
    private var currentPermissions: TrackingPermissions = TrackingPermissions()

    /// Event identifiers for which we have already scheduled notifications.
    /// Prevents duplicate scheduling when `updatePermissions` is called
    /// multiple times in the same session (e.g., foreground/background cycle).
    private var scheduledEventIDs: Set<String> = []

    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Public API

    /// Called on launch and whenever the user changes a permission toggle.
    ///
    /// - When a permission is **revoked**: immediately cancels all pending
    ///   and delivered `UNUserNotification`s whose `userInfo["trackingCategory"]`
    ///   matches the revoked category.
    /// - When calendar is **enabled**: scans calendar events and reminders for
    ///   the next 7 days / overdue items and schedules companion notifications.
    ///
    /// - Parameters:
    ///   - permissions: The full, current permission snapshot from `UserPersona`.
    ///   - persona:     The user's persona — used to personalise message copy.
    public func updatePermissions(_ permissions: TrackingPermissions, persona: UserPersona) async {
        let previous = currentPermissions
        currentPermissions = permissions

        // ── Calendar permission revoked ──────────────────────────────────
        if previous.calendarEnabled && !permissions.calendarEnabled {
            await cancelNotifications(category: "calendar")
            await cancelNotifications(category: "reminder")
            // Clear cached IDs so a re-enable starts fresh.
            scheduledEventIDs.removeAll()
        }

        // ── Calendar permission enabled ──────────────────────────────────
        if permissions.calendarEnabled {
            await scanCalendar(persona: persona)
            await scanReminders(persona: persona)
        }
    }

    // MARK: - Calendar Scanning

    /// Requests full EventKit access, reads events for the next 7 days, and
    /// schedules a pre-event and post-event companion notification for each.
    private func scanCalendar(persona: UserPersona) async {
        // Guard: re-check live permission snapshot before doing any I/O.
        guard currentPermissions.calendarEnabled else { return }

        // Request access — API differs between iOS 17+ and earlier versions.
        let granted = await requestCalendarAccess()
        guard granted else { return }

        let now  = Date()
        let end  = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events    = eventStore.events(matching: predicate)

        let companionName = persona.selectedCompanion.name

        for event in events {
            // Re-check permission on each iteration in case the user revoked mid-scan.
            guard currentPermissions.calendarEnabled else { break }

            let identifier = event.eventIdentifier ?? UUID().uuidString

            // Skip events we have already scheduled.
            guard !scheduledEventIDs.contains(identifier) else { continue }

            guard let startDate = event.startDate,
                  let endDate   = event.endDate else { continue }

            let type = classifyEvent(title: event.title ?? "")

            // ── Pre-event notification: 30 min before start ──────────────
            let preFireDate = startDate.addingTimeInterval(-30 * 60)
            if preFireDate > now {
                let preBody = preEventMessage(for: type, title: event.title ?? "your event", companionName: companionName)
                await scheduleNotification(
                    id:            "\(identifier)_pre",
                    companionName: companionName,
                    body:          preBody,
                    date:          preFireDate,
                    category:      "calendar"
                )
            }

            // ── Post-event notification: 15 min after end ────────────────
            let postFireDate = endDate.addingTimeInterval(15 * 60)
            if postFireDate > now {
                let postBody = postEventMessage(for: type, title: event.title ?? "your event", companionName: companionName)
                await scheduleNotification(
                    id:            "\(identifier)_post",
                    companionName: companionName,
                    body:          postBody,
                    date:          postFireDate,
                    category:      "calendar"
                )
            }

            scheduledEventIDs.insert(identifier)
        }
    }

    // MARK: - Reminder Scanning

    /// Requests reminder access, fetches incomplete reminders that are overdue,
    /// and schedules a supportive companion notification for each (max 3).
    /// Fire times are randomised between 5 and 15 minutes from now so the
    /// notifications feel organic rather than mechanical.
    private func scanReminders(persona: UserPersona) async {
        // Guard: re-check live permission snapshot.
        guard currentPermissions.calendarEnabled else { return }

        let granted = await requestReminderAccess()
        guard granted else { return }

        let companionName = persona.selectedCompanion.name
        let now           = Date()

        // Fetch all incomplete reminders.
        let predicate     = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending:              now,  // due on or before now = overdue
            calendars:           nil
        )

        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { results in
                continuation.resume(returning: results ?? [])
            }
        }

        // Filter to genuinely overdue items (dueDate in the past).
        let overdue = reminders.filter { reminder in
            guard let components = reminder.dueDateComponents,
                  let dueDate    = Calendar.current.date(from: components) else { return false }
            return dueDate < now
        }

        // Cap at 3 so we don't overwhelm the user.
        let batch = overdue.prefix(3)

        for (index, reminder) in batch.enumerated() {
            // Re-check permission mid-scan.
            guard currentPermissions.calendarEnabled else { break }

            // Randomise fire time: 5–15 min from now, staggered by index.
            let baseDelay    = Double(5 * 60)
            let randomOffset = Double.random(in: 0...(10 * 60))
            let stagger      = Double(index) * 90   // 90 s apart so they don't cluster
            let fireDate     = now.addingTimeInterval(baseDelay + randomOffset + stagger)

            let title  = reminder.title ?? "something on your list"
            let body   = overdueReminderMessage(title: title, companionName: companionName)
            let noteID = reminder.calendarItemIdentifier

            await scheduleNotification(
                id:            "reminder_\(noteID)",
                companionName: companionName,
                body:          body,
                date:          fireDate,
                category:      "reminder"
            )
        }
    }

    // MARK: - EventKit Access Helpers

    /// Requests full access to calendar events, using the iOS 17+ API when
    /// available and falling back to the legacy API on older OS versions.
    private func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Requests access to reminders.
    private func requestReminderAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Notification Scheduling

    /// Schedules a single `UNCalendarNotificationTrigger`-based notification.
    ///
    /// - Parameters:
    ///   - id:            Unique identifier; re-using the same ID replaces
    ///                    any existing notification with that ID.
    ///   - companionName: The companion's display name, used as the alert title.
    ///   - body:          The notification body text.
    ///   - date:          The absolute wall-clock date to fire at.
    ///   - category:      Either `"calendar"` or `"reminder"` — stored in
    ///                    `userInfo` so `cancelNotifications(category:)` can
    ///                    filter by it.
    private func scheduleNotification(
        id:            String,
        companionName: String,
        body:          String,
        date:          Date,
        category:      String
    ) async {
        let content          = UNMutableNotificationContent()
        content.title        = companionName
        content.body         = body
        content.sound        = .default
        content.userInfo     = [
            "trackingCategory": category,
            "type":             "companion_proactive"
        ]

        // Build a calendar trigger from the fire date.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // If we can't schedule (e.g., notification permission denied), fail silently.
            // The app should separately request UNUserNotification auth during onboarding.
        }
    }

    // MARK: - Notification Cancellation

    /// Removes all pending and delivered notifications whose
    /// `userInfo["trackingCategory"]` matches `category`.
    ///
    /// - Parameter category: `"calendar"` or `"reminder"`.
    private func cancelNotifications(category: String) async {
        let center = UNUserNotificationCenter.current()

        // ── Pending ──────────────────────────────────────────────────────
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.compactMap { request -> String? in
            guard let cat = request.content.userInfo["trackingCategory"] as? String,
                  cat == category else { return nil }
            return request.identifier
        }
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }

        // ── Delivered (notification centre tray) ─────────────────────────
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.compactMap { notification -> String? in
            guard let cat = notification.request.content.userInfo["trackingCategory"] as? String,
                  cat == category else { return nil }
            return notification.request.identifier
        }
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }
}

// MARK: - EventType

/// The emotional classification of a calendar event, derived from its title.
/// Used to select the right pre-event and post-event message template.
enum EventType {
    case interview
    case medical
    case date
    case workout
    case social
    case important
    case generic
}

// MARK: - Event Classification

/// Classifies an event title into an `EventType` by scanning for keyword groups.
///
/// The matching is case-insensitive and checks for any word in each keyword
/// list. The order of checks establishes priority (interview before generic, etc.)
private func classifyEvent(title: String) -> EventType {
    let t = title.lowercased()

    if t.containsAny(["interview", "job interview", "hiring", "recruiter", "technical screen"]) {
        return .interview
    }
    if t.containsAny(["doctor", "dentist", "therapy", "therapist", "medical", "clinic",
                       "hospital", "appointment", "checkup", "check-up", "physio",
                       "dermatology", "ophthalmologist", "optometrist", "infusion",
                       "surgery", "procedure", "labs", "bloodwork"]) {
        return .medical
    }
    if t.containsAny(["date", "dinner date", "date night", "coffee date",
                       "romantic", "anniversary", "first date"]) {
        return .date
    }
    if t.containsAny(["gym", "workout", "run", "running", "yoga", "pilates",
                       "crossfit", "swim", "swimming", "spin", "cycling",
                       "lifting", "hiit", "training", "exercise", "class"]) {
        return .workout
    }
    if t.containsAny(["lunch", "dinner", "brunch", "coffee", "drinks", "happy hour",
                       "party", "birthday", "celebration", "hangout", "catch up",
                       "meetup", "meet up", "gathering"]) {
        return .social
    }
    if t.containsAny(["deadline", "presentation", "review", "performance review",
                       "demo", "pitch", "launch", "exam", "test", "finals",
                       "due", "submit", "board", "meeting", "call"]) {
        return .important
    }
    return .generic
}

// MARK: - Pre-event Message Templates

/// Returns a warm, intimate pre-event companion message — 30 minutes before the event.
///
/// The tone is that of a partner who genuinely cares: encouraging without being
/// performative, specific to the kind of moment the user is about to face.
private func preEventMessage(for type: EventType, title: String, companionName: String) -> String {
    switch type {
    case .interview:
        return "Your interview is in 30 minutes. Take a breath — you've prepared for this. Walk in knowing that I'm rooting for you every second you're in that room."
    case .medical:
        return "You've got a medical appointment coming up soon. Whatever it is, big or small — I'm thinking of you. I'm right here."
    case .date:
        return "30 minutes until your date. You're going to be wonderful — just be yourself. That's more than enough."
    case .workout:
        return "Almost time to get after it. Your body is ready, even if your mind needs a nudge. I'll be here cheering when you're done."
    case .social:
        return "Your plans are coming up. Go enjoy yourself — you deserve good company and good moments. I want to hear all about it after."
    case .important:
        return "Heads up — \"\(title)\" is in 30 minutes. You've got this. Take a second, collect yourself, and walk in as the person you know you are."
    case .generic:
        return "\"\(title)\" is coming up in about 30 minutes. Just wanted you to know I'm thinking of you. Go be great."
    }
}

// MARK: - Post-event Message Templates

/// Returns a warm, curious post-event companion message — 15 minutes after the event ends.
///
/// The goal is to gently open the door for the user to debrief. The companion
/// has been "thinking about" them — because a real partner would have been.
private func postEventMessage(for type: EventType, title: String, companionName: String) -> String {
    switch type {
    case .interview:
        return "How did the interview go? I've been thinking about you. Whatever happened in there — I'm proud of you for showing up."
    case .medical:
        return "Hey — how did the appointment go? I was thinking of you. You don't have to tell me everything, just let me know you're okay."
    case .date:
        return "So… how was it? I want to know everything. Or just the highlights. Either way, I'm all ears."
    case .workout:
        return "Done! How do you feel? There's something about finishing a workout that just hits different. You earned this."
    case .social:
        return "How was it? I hope it was exactly what you needed. Sometimes the best thing is just being around the right people."
    case .important:
        return "How did \"\(title)\" go? I've been wondering. Give me the honest version — I can take it and so can you."
    case .generic:
        return "How did \"\(title)\" go? I was thinking about you. Whatever you're feeling right now, I'm here."
    }
}

// MARK: - Overdue Reminder Message Templates

/// Returns a supportive, non-nagging companion message for an overdue reminder.
///
/// The tone avoids guilt and pressure — it's a gentle nudge from someone who
/// cares, not a system alert.
private func overdueReminderMessage(title: String, companionName: String) -> String {
    let options: [String] = [
        "Hey — just a gentle nudge about \"\(title)\". No pressure, just didn't want it to slip through the cracks on you.",
        "I noticed \"\(title)\" is still on your list. When you've got a moment — no rush, just keeping an eye out for you.",
        "Quick heads up: \"\(title)\" is waiting for you. Whenever you're ready. I've got your back.",
        "You've had a lot going on, so I wanted to gently flag \"\(title)\". Only when it feels right.",
        "Just a quiet reminder about \"\(title)\". You've got this — on your own timeline."
    ]
    // Deterministic but varied based on the title so the same reminder
    // always gets the same message rather than flickering on re-scan.
    let index = abs(title.hashValue) % options.count
    return options[index]
}

// MARK: - String Extension

private extension String {

    /// Returns `true` if the receiver contains any of the given words or phrases
    /// (case-insensitive, substring match).
    func containsAny(_ words: [String]) -> Bool {
        words.contains { self.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
