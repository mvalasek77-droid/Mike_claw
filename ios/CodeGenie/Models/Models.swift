import Foundation
import SwiftUI

struct AppDescription: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var prompt: String
    var category: Category
    var style: Style
    var features: [String]

    init(id: UUID = .init(), title: String, prompt: String, category: Category = .utility, style: Style = .liquidGlass, features: [String] = []) {
        self.id = id; self.title = title; self.prompt = prompt
        self.category = category; self.style = style; self.features = features
    }

    enum Category: String, Codable, CaseIterable, Identifiable {
        case utility, productivity, lifestyle, finance, social, health, education, games, photo
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .utility: "wrench.and.screwdriver.fill"
            case .productivity: "checklist"
            case .lifestyle: "leaf.fill"
            case .finance: "dollarsign.circle.fill"
            case .social: "bubble.left.and.bubble.right.fill"
            case .health: "heart.fill"
            case .education: "graduationcap.fill"
            case .games: "gamecontroller.fill"
            case .photo: "photo.on.rectangle.angled"
            }
        }
    }

    enum Style: String, Codable, CaseIterable, Identifiable {
        case liquidGlass, minimal, playful, editorial
        var id: String { rawValue }
        var label: String {
            switch self {
            case .liquidGlass: "Liquid Glass"
            case .minimal: "Minimal"
            case .playful: "Playful"
            case .editorial: "Editorial"
            }
        }
    }
}

struct BuildJob: Identifiable, Hashable, Codable {
    let id: UUID
    let description: AppDescription
    var stage: Stage
    var startedAt: Date
    var finishedAt: Date?
    var artifactURL: URL?
    var simulatorPreviewURL: URL?

    init(id: UUID = .init(), description: AppDescription, stage: Stage = .planning, startedAt: Date = .now) {
        self.id = id; self.description = description; self.stage = stage; self.startedAt = startedAt
    }

    enum Stage: String, CaseIterable, Hashable, Codable {
        case planning      = "Planning architecture"
        case scaffolding   = "Scaffolding Xcode project"
        case generatingUI  = "Generating UI"
        case wiringLogic   = "Wiring logic"
        case linting       = "Linting & polish"
        case buildingIPA   = "Building IPA"
        case readyForTest  = "Ready to test"
        case shipping      = "Ready to ship"
        case failed        = "Build failed"

        var progress: Double {
            switch self {
            case .planning: 0.05
            case .scaffolding: 0.18
            case .generatingUI: 0.38
            case .wiringLogic: 0.58
            case .linting: 0.74
            case .buildingIPA: 0.88
            case .readyForTest: 0.96
            case .shipping: 1.0
            case .failed: 1.0
            }
        }

        /// What the user reads.
        ///
        /// `rawValue` is the persistence key — it is written into
        /// UserDefaults for every saved job — so it must not change or
        /// existing galleries fail to decode and empty themselves.
        /// Display text lives here instead, which also lets it drop
        /// jargon like "IPA" that means nothing to a first-time
        /// builder.
        var label: String {
            switch self {
            case .planning:     "Planning your app"
            case .scaffolding:  "Setting up the project"
            case .generatingUI: "Designing the screens"
            case .wiringLogic:  "Making it work"
            case .linting:      "Polishing"
            case .buildingIPA:  "Packaging your app"
            case .readyForTest: "Ready to try"
            case .shipping:     "Ready to send to Apple"
            case .failed:       "Something went wrong"
            }
        }

        var systemImage: String {
            switch self {
            case .planning: "rectangle.3.group"
            case .scaffolding: "shippingbox.fill"
            case .generatingUI: "paintbrush.pointed.fill"
            case .wiringLogic: "bolt.horizontal.fill"
            case .linting: "sparkles"
            case .buildingIPA: "hammer.fill"
            case .readyForTest: "play.circle.fill"
            case .shipping: "paperplane.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

        var humanCopy: String {
            switch self {
            case .planning:     "Mapping out screens and data flow."
            case .scaffolding:  "Creating the Xcode project, targets, and asset catalog."
            case .generatingUI: "Drawing your interface in SwiftUI with Liquid Glass."
            case .wiringLogic:  "Connecting models, services, and persistence."
            case .linting:      "Polishing animations, accessibility, and dark mode."
            case .buildingIPA:  "Turning the code into an app your iPhone can install."
            case .readyForTest: "Open the preview to try it live."
            case .shipping:     "Ready to send to Apple."
            case .failed:       "We hit a build error — let's diagnose."
            }
        }
    }
}

struct AppStoreMetadata: Codable, Hashable {
    var name: String
    var subtitle: String
    var primaryCategory: String
    var keywords: [String]
    var description: String
    var promotionalText: String
    var supportURL: String
    var marketingURL: String
    var ageRating: String
    var price: String
}
