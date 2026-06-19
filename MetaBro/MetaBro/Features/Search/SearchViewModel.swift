import SwiftUI

/// Debounced search over communities + posts. The View binds its search text to
/// `query`; the model debounces, calls the service, and publishes results.
@MainActor
@Observable
final class SearchViewModel {
    enum State: Equatable {
        case idle           // empty query
        case searching
        case results(SearchResults)
        case empty(String)  // query with no matches
        case error(String)
    }

    private(set) var state: State = .idle
    private let service: SearchService
    private var task: Task<Void, Never>?

    init(service: SearchService) {
        self.service = service
    }

    /// Called on every keystroke; debounces before hitting the service.
    func query(_ text: String) {
        task?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }

        task = Task {
            state = .searching
            try? await Task.sleep(nanoseconds: 250_000_000) // debounce
            if Task.isCancelled { return }
            do {
                let results = try await service.search(trimmed)
                if Task.isCancelled { return }
                state = results.isEmpty ? .empty(trimmed) : .results(results)
            } catch {
                state = .error("Search failed. Try again.")
            }
        }
    }
}
