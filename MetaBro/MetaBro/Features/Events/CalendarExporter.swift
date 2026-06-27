import EventKit

/// One-shot "Add to Calendar" — requests access, then saves a single event.
/// No persistent store reference is kept; each call is self-contained.
enum CalendarExporter {
    enum Result { case added, denied, failed }

    static func add(_ event: Event) async -> Result {
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            BroLog.error(error, category: "calendar")
            return .failed
        }
        guard granted else { return .denied }

        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = event.title
        ekEvent.notes = event.details
        ekEvent.location = event.location
        ekEvent.startDate = event.startDate
        ekEvent.endDate = event.startDate.addingTimeInterval(2 * 3_600)
        ekEvent.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(ekEvent, span: .thisEvent)
            return .added
        } catch {
            BroLog.error(error, category: "calendar")
            return .failed
        }
    }
}
