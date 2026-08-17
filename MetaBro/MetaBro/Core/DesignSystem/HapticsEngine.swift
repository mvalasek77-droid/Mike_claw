import UIKit

/// Adaptive haptics for MetaBro. Each interaction has a distinct texture so the
/// app *feels* responsive. Cheap generators are reused; intensity scales with
/// the weight of the action.
@MainActor
final class HapticsEngine {
    static let shared = HapticsEngine()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {}

    /// Call before a burst of haptics to reduce latency.
    func prepare() {
        impactLight.prepare()
        impactRigid.prepare()
    }

    enum Event {
        case vote        // crisp tick
        case reaction    // soft tap
        case award       // rich pop
        case refreshDone // success
        case error       // warning
        case selectionChanged
    }

    func play(_ event: Event) {
        switch event {
        case .vote:
            impactRigid.impactOccurred(intensity: 0.8)
        case .reaction:
            impactLight.impactOccurred(intensity: 0.5)
        case .award:
            impactRigid.impactOccurred(intensity: 1.0)
        case .refreshDone:
            notification.notificationOccurred(.success)
        case .error:
            notification.notificationOccurred(.warning)
        case .selectionChanged:
            selection.selectionChanged()
        }
    }
}
