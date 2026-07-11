import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var children: [Child] = []
    @Published var alertsByChild: [Int: [SafetyAlert]] = [:]
    @Published var resources: [SafetyResource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            children = try await api.listChildren()
            for child in children {
                alertsByChild[child.id] = try await api.alerts(childId: child.id)
            }
            if resources.isEmpty {
                resources = try await api.resources()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func linkChild(username: String, parentName: String) async -> Bool {
        do {
            let child = try await api.linkChild(username: username, parentName: parentName)
            children.append(child)
            try await api.refresh(childId: child.id)
            alertsByChild[child.id] = try await api.alerts(childId: child.id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func unlinkChild(_ child: Child) async {
        do {
            try await api.unlinkChild(id: child.id)
            children.removeAll { $0.id == child.id }
            alertsByChild[child.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(_ child: Child) async {
        do {
            try await api.refresh(childId: child.id)
            alertsByChild[child.id] = try await api.alerts(childId: child.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acknowledge(_ alert: SafetyAlert, for child: Child) async {
        do {
            try await api.acknowledge(alertId: alert.id)
            alertsByChild[child.id]?.removeAll { $0.id == alert.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
