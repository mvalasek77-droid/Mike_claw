#if os(watchOS)
import Foundation

/// Persists `Progression` to `UserDefaults`. Tiny wrapper kept off the pure
/// model so the engine stays dependency-free and testable.
enum ProgressionStore {
    private static let key = "eternalcombat.progression.v1"

    static func load() -> Progression {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(Progression.self, from: data)
        else { return Progression() }
        return p
    }

    static func save(_ p: Progression) {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
#endif
