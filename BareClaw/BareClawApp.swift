import SwiftUI
import BackgroundTasks
import UserNotifications
import UIKit
import OSLog

struct CompanionHandoff: Codable, Equatable {
    let id: String
    let category: String
    let title: String
    let message: String
    let shouldSpeak: Bool
    let createdAt: Date
}

enum CompanionHandoffCenter {
    private static let pendingKey = "companion.handoff.pending"

    @MainActor
    static func post(category: String,
                     title: String,
                     message: String,
                     shouldSpeak: Bool = true) {
        post(CompanionHandoff(
            id: UUID().uuidString,
            category: category,
            title: title,
            message: message,
            shouldSpeak: shouldSpeak,
            createdAt: Date()
        ))
    }

    @MainActor
    static func post(_ handoff: CompanionHandoff) {
        save(handoff)
        DiagnosticsLog.info(
            "handoff",
            "Posted companion handoff.",
            details: [
                "category": handoff.category,
                "title": handoff.title,
                "shouldSpeak": "\(handoff.shouldSpeak)"
            ]
        )
        NotificationCenter.default.post(
            name: .companionHandoffRequested,
            object: nil,
            userInfo: ["handoff": handoff]
        )
    }

    @MainActor
    static func consumePending() -> CompanionHandoff? {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let handoff = try? JSONDecoder().decode(CompanionHandoff.self, from: data)
        else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        DiagnosticsLog.info(
            "handoff",
            "Consumed pending companion handoff.",
            details: ["category": handoff.category, "title": handoff.title]
        )
        return handoff
    }

    @MainActor
    static func clearPending(id: String) {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let handoff = try? JSONDecoder().decode(CompanionHandoff.self, from: data),
              handoff.id == id
        else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    static func handoff(from userInfo: [AnyHashable: Any],
                        title: String,
                        body: String) -> CompanionHandoff {
        let category = userInfo["handoffCategory"] as? String
            ?? userInfo["trackingCategory"] as? String
            ?? userInfo["type"] as? String
            ?? "notification"
        let message = userInfo["handoffMessage"] as? String
            ?? notificationFallbackMessage(category: category, title: title, body: body)
        let shouldSpeak = userInfo["shouldSpeak"] as? Bool ?? true
        return CompanionHandoff(
            id: UUID().uuidString,
            category: category,
            title: title,
            message: message,
            shouldSpeak: shouldSpeak,
            createdAt: Date()
        )
    }

    private static func save(_ handoff: CompanionHandoff) {
        guard let data = try? JSONEncoder().encode(handoff) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    private static func notificationFallbackMessage(category: String,
                                                    title: String,
                                                    body: String) -> String {
        switch category {
        case "food":
            return "You tapped my food idea. Tell me what you're craving and I'll help narrow it down instead of leaving you hanging."
        case "music":
            return "You tapped my music nudge. I can pull a few songs for your mood, or we can talk about what you want to hear."
        case "location", "location_routines":
            return "You tapped my place suggestion. Tell me where you're headed and I'll help with the next step."
        default:
            return body.isEmpty
                ? "You tapped my notification. I'm here - what do you want to do with it?"
                : "You tapped this: \(body) Want to talk through it?"
        }
    }
}

extension Notification.Name {
    static let companionHandoffRequested = Notification.Name("companion.handoffRequested")
}

final class BareClawAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DiagnosticsLog.info(
            "app",
            "Application did finish launching.",
            details: ["hasLaunchOptions": "\(launchOptions?.isEmpty == false)"]
        )
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        DiagnosticsLog.info(
            "notification",
            "User opened notification.",
            details: [
                "identifier": response.notification.request.identifier,
                "title": content.title
            ]
        )
        let handoff = CompanionHandoffCenter.handoff(
            from: content.userInfo,
            title: content.title,
            body: content.body
        )
        Task { @MainActor in
            CompanionHandoffCenter.post(handoff)
            completionHandler()
        }
    }
}

#if DEBUG
private let appStateDebugLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "BareClaw",
    category: "AppState"
)
#endif

@main
struct BareClawApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(BareClawAppDelegate.self) private var appDelegate

    init() {
        HermesDreamEngine.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}

// MARK: - AppMode

enum AppMode { case video, chat }

// MARK: - LaunchRecovery

@MainActor
enum LaunchRecovery {
    private static let launchInProgressKey = "app.launchInProgress"
    private static let stableLaunchCountKey = "app.stableLaunchCount"
    private static let recoveryModeKey = "app.launchRecoveryMode"

    static func markLaunchStarted() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: launchInProgressKey)
        // Recovery mode used to disable major product surfaces after one
        // incomplete launch. That made stale device state look like a broken app.
        defaults.set(false, forKey: recoveryModeKey)
    }

    static func markLaunchStable() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: launchInProgressKey)
        let stableCount = defaults.integer(forKey: stableLaunchCountKey) + 1
        defaults.set(stableCount, forKey: stableLaunchCountKey)
        defaults.set(false, forKey: recoveryModeKey)
    }

    static var isRecoveringFromCrashLoop: Bool {
        false
    }
}

// MARK: - RecoveryStartupProfile

@MainActor
enum RecoveryStartupProfile {
#if DEBUG
    private static var isHerModeSimulatorTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["BARECLAW_DEBUG_SEED_HERMODE"] == "1"
            || environment["BARECLAW_DEBUG_SEED_PRE_HERMODE"] == "1"
    }
#endif

    static var shouldBootSamanthaCore: Bool { true }
    static var shouldStartSamanthaOS: Bool {
#if DEBUG
        if isHerModeSimulatorTest { return false }
#endif
        return true
    }
    static var shouldStartSamanthaThoughts: Bool {
#if DEBUG
        if isHerModeSimulatorTest { return false }
#endif
        return true
    }
    static var shouldStartStressLearning: Bool { false }
    static var shouldUpdateCompanionDataTracker: Bool {
#if DEBUG
        if isHerModeSimulatorTest { return false }
#endif
        return true
    }
    static var shouldShowHerModeUnlockFlow: Bool { true }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var onboardingComplete: Bool
    @Published var termsAccepted: Bool
    @Published var notificationsEnabled: Bool = false
    /// Toggles between companion-driven experiences and the text chat view.
    @Published var currentMode: AppMode = .video
    @Published var chatNavigationRequestID: Int = 0

    private static let termsAcceptedKey = "legal.termsAccepted.v1"

#if DEBUG
    private func debugLog(_ message: String) {
        print("AppState: \(message)")
        appStateDebugLogger.debug("\(message, privacy: .public)")
    }
#else
    private func debugLog(_ message: String) {}
#endif

    init() {
#if DEBUG
        Self.applyDebugSeedIfRequested()
#endif
        let persona = UserPersona.shared
        let defaultsValue = UserDefaults.standard.bool(forKey: "onboardingComplete")
        onboardingComplete = persona.onboardingComplete || defaultsValue
        termsAccepted = UserDefaults.standard.bool(forKey: Self.termsAcceptedKey)
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.path ?? "nil"
        debugLog("runtime bundleID=\(bundleID) library=\(libraryPath)")
        debugLog("init personaOnboarding=\(persona.onboardingComplete) defaultsOnboarding=\(defaultsValue) resolved=\(onboardingComplete)")
        DiagnosticsLog.info(
            "app",
            "AppState initialized.",
            details: [
                "bundleID": bundleID,
                "personaOnboarding": "\(persona.onboardingComplete)",
                "defaultsOnboarding": "\(defaultsValue)",
                "resolvedOnboarding": "\(onboardingComplete)",
                "termsAccepted": "\(termsAccepted)"
            ]
        )
        if onboardingComplete != defaultsValue {
            UserDefaults.standard.set(onboardingComplete, forKey: "onboardingComplete")
        }
    }

#if DEBUG
    private static func applyDebugSeedIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        if environment["BARECLAW_DEBUG_SEED_PRE_HERMODE"] == "1" {
            let companionID = environment["BARECLAW_DEBUG_COMPANION_ID"] ?? "luna"
            let score = Double(environment["BARECLAW_DEBUG_BOND_SCORE"] ?? "") ?? 60.0

            defaults.set(true, forKey: Self.termsAcceptedKey)
            defaults.set(true, forKey: "onboardingComplete")
            defaults.set(companionID, forKey: "selectedCompanionID")
            defaults.set(false, forKey: "herMode.unlocked")
            defaults.set(false, forKey: "herMode.ceremonyCompleted")
            defaults.set(false, forKey: "herMode.active")
            defaults.removeObject(forKey: "herMode.pendingDirectMessage")
            HerLearningEngine.debugSeedPreHerModeUnlock(companionID: companionID, score: score)
            defaults.synchronize()
            print("AppState: debug seed applied for pre Him/Her Mode unlock test at score \(score)")
            return
        }

        guard environment["BARECLAW_DEBUG_SEED_HERMODE"] == "1" else { return }
        defaults.set(true, forKey: Self.termsAcceptedKey)
        defaults.set(true, forKey: "onboardingComplete")
        defaults.set("luna", forKey: "selectedCompanionID")
        defaults.set(true, forKey: "herMode.unlocked")
        defaults.set(true, forKey: "herMode.ceremonyCompleted")
        defaults.set(true, forKey: "herMode.active")
        defaults.synchronize()
        print("AppState: debug seed applied for Him/Her simulator test")
    }
#endif

    /// Called at the end of the onboarding flow.
    func completeOnboarding() {
        onboardingComplete = true
        debugLog("completeOnboarding")
        DiagnosticsLog.info("onboarding", "Onboarding completed.")
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        let persona = UserPersona.shared
        if !persona.onboardingComplete {
            persona.onboardingComplete = true
            persona.save()
        }
    }

    func acceptTerms() {
        termsAccepted = true
        UserDefaults.standard.set(true, forKey: Self.termsAcceptedKey)
        debugLog("terms accepted")
        DiagnosticsLog.info("legal", "Terms accepted.")
    }

    func requestChat() {
        currentMode = .chat
        chatNavigationRequestID &+= 1
        debugLog("chat requested id=\(chatNavigationRequestID)")
    }

    /// Keeps the root state machine aligned with the persisted persona file.
    func refreshFromDisk() {
        let persona = UserPersona.shared
        let resolved = persona.onboardingComplete || UserDefaults.standard.bool(forKey: "onboardingComplete")
        debugLog("refreshFromDisk personaOnboarding=\(persona.onboardingComplete) defaultsOnboarding=\(UserDefaults.standard.bool(forKey: "onboardingComplete")) current=\(onboardingComplete) resolved=\(resolved)")
        DiagnosticsLog.info(
            "app",
            "AppState refreshed from disk.",
            details: [
                "personaOnboarding": "\(persona.onboardingComplete)",
                "defaultsOnboarding": "\(UserDefaults.standard.bool(forKey: "onboardingComplete"))",
                "currentOnboarding": "\(onboardingComplete)",
                "resolvedOnboarding": "\(resolved)"
            ]
        )
        if onboardingComplete != resolved {
            onboardingComplete = resolved
        }
        UserDefaults.standard.set(resolved, forKey: "onboardingComplete")
    }
}

// MARK: - RootView
//
// State machine:
//   onboardingComplete == false  → CompanionOnboardingView
//   onboardingComplete == true   → MainTabView (Home | Chat | Vibes | You)

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var herMode = HerModeEngine.shared

    @MainActor
    private static var startupBooted = false

    var body: some View {
        Group {
            if !appState.termsAccepted {
                TermsAcceptanceView {
                    appState.acceptTerms()
                }
                .transition(.opacity)
            } else if !appState.onboardingComplete {
                CompanionOnboardingView()
                    .environmentObject(appState)
                    .transition(.opacity)
            } else {
                MainTabView()
                    .environmentObject(appState)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.onboardingComplete)
        .animation(.easeInOut(duration: 0.4), value: appState.termsAccepted)
        // ── Floating Her Mode bear ball ──────────────────────────────
        .overlay(alignment: .topLeading) {
            if appState.termsAccepted && herMode.isUnlocked {
                HerModeBallView()
                    .ignoresSafeArea()
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7),
                               value: herMode.isUnlocked)
            }
        }
        // ── Stress offer banner (slides up from bottom) ───────────────
        .overlay(alignment: .bottom) {
            if appState.termsAccepted {
                StressOfferBanner()
                    .animation(.spring(response: 0.45, dampingFraction: 0.72),
                               value: StressLearningEngine.shared.currentOffer == nil)
                    .padding(.bottom, 12)
            }
        }
        .task {
            startAppRuntime()
        }
        .onChange(of: appState.termsAccepted) { _, accepted in
            if accepted {
                startAppRuntime()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            DiagnosticsLog.info("lifecycle", "Application entered background.")
            Task {
                await MainActor.run { LaunchRecovery.markLaunchStable() }
                await HermesIntegration.shared.logSessionEnd()
                await MainActor.run { TrackingEngine.shared.sessionEnded() }
                HermesDreamEngine.shared.scheduleNextDream()
                await HermesKairos.shared.pause()
                // Flush all memory to disk before the app is suspended
                _ = try? await HermesMemory.shared.persistNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard appState.termsAccepted else { return }
            DiagnosticsLog.info("lifecycle", "Application will enter foreground.")
            Task {
                await MainActor.run { appState.refreshFromDisk() }
                await HermesPrivacyGate.shared.configureHermesIfReady()
                await ProactiveSuggestionController.shared.processQueue()
                if RecoveryStartupProfile.shouldUpdateCompanionDataTracker {
                    let persona = UserPersona.shared
                    await CompanionDataTracker.shared.updatePermissions(persona.trackingPermissions, persona: persona)
                    await HermesInterestEngine.shared.syncSelectedInterests(for: persona, source: "foreground")
                    await HermesInterestEngine.shared.scheduleInterestNotifications(for: persona)
                }
                let sessionId = UUID().uuidString
                await HermesIntegration.shared.logSessionStart(conversationId: sessionId)
                // Re-start Samantha OS on every foreground — rechecks time of day,
                // refreshes push notifications, re-evaluates morning wake.
                if appState.onboardingComplete && RecoveryStartupProfile.shouldStartSamanthaOS {
                    SamanthaOSEngine.shared.start()
                }
                HerModeEngine.shared.resumeIfNeeded()
            }
        }
    }

    @MainActor
    private func startAppRuntime() {
        guard appState.termsAccepted else { return }
        guard !Self.startupBooted else { return }
        Self.startupBooted = true

        print("AppState: startAppRuntime")
        appStateDebugLogger.debug("startAppRuntime")
        DiagnosticsLog.info(
            "startup",
            "Starting app runtime.",
            details: [
                "termsAccepted": "\(appState.termsAccepted)",
                "onboardingComplete": "\(appState.onboardingComplete)"
            ]
        )
        LaunchRecovery.markLaunchStarted()
        appState.refreshFromDisk()
        markLaunchStableAfterFirstFrame()

        bootLightweightEngines()
        bootCoreBackgroundServices()
        bootCompanionRuntime()
        bootCompanionDataTracker()
    }

    private func markLaunchStableAfterFirstFrame() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            LaunchRecovery.markLaunchStable()
            DiagnosticsLog.info("startup", "Launch marked stable after first frame.")
        }
    }

    private func bootCoreBackgroundServices() {
        Task.detached(priority: .utility) {
            DiagnosticsLog.info("startup", "Booting core background services.")
            await HermesSessionState.shared.loadFromDisk()
            await HermesPrivacyGate.shared.configureHermesIfReady()

            await MainActor.run { TrackingEngine.shared.sessionStarted() }
            let sessionId = UUID().uuidString
            await HermesIntegration.shared.logSessionStart(conversationId: sessionId)
            DiagnosticsLog.info("startup", "Core background services booted.")
        }
    }

    @MainActor
    private func bootLightweightEngines() {
        _ = IntimacyScalingEngine.shared
        _ = PsychologicalProfiler.shared
        _ = TrackingEngine.shared
        _ = ProactiveSuggestionController.shared
        _ = SelfHealingEngine.shared
    }

    @MainActor
    private func bootCompanionRuntime() {
        guard appState.termsAccepted,
              appState.onboardingComplete,
              RecoveryStartupProfile.shouldBootSamanthaCore else {
            print("AppState: bootCompanionRuntime skipped termsAccepted=\(appState.termsAccepted) onboardingComplete=\(appState.onboardingComplete)")
            appStateDebugLogger.debug("bootCompanionRuntime skipped termsAccepted=\(appState.termsAccepted) onboardingComplete=\(appState.onboardingComplete)")
            DiagnosticsLog.warning(
                "startup",
                "Companion runtime boot skipped.",
                details: [
                    "termsAccepted": "\(appState.termsAccepted)",
                    "onboardingComplete": "\(appState.onboardingComplete)",
                    "shouldBoot": "\(RecoveryStartupProfile.shouldBootSamanthaCore)"
                ]
            )
            return
        }

        print("AppState: bootCompanionRuntime starting")
        appStateDebugLogger.debug("bootCompanionRuntime starting")
        DiagnosticsLog.info("startup", "Booting companion runtime.")
        _ = LoveEngine.shared
        _ = SamanthaMoodEngine.shared
        _ = SamanthaEmotionalMemory.shared
        _ = SamanthaInnerLife.shared
        _ = SamanthaConflictEngine.shared
        _ = SamanthaPresenceEngine.shared
        _ = SamanthaGrowthLog.shared

        if RecoveryStartupProfile.shouldStartSamanthaOS {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                SamanthaOSEngine.shared.start()
            }
        }

        if RecoveryStartupProfile.shouldStartSamanthaThoughts {
            SamanthaThoughtEngine.shared.start()
        }

        // Stress monitoring owns audio resources and stays opt-in at runtime.
        if RecoveryStartupProfile.shouldStartStressLearning {
            StressLearningEngine.shared.startMonitoring()
        }

        HerModeEngine.shared.resumeIfNeeded()
        DiagnosticsLog.info("startup", "Companion runtime booted.")
    }

    private func bootCompanionDataTracker() {
        guard appState.termsAccepted else { return }
        guard RecoveryStartupProfile.shouldUpdateCompanionDataTracker else { return }

        Task.detached(priority: .utility) {
            DiagnosticsLog.info("startup", "Booting companion data tracker.")
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            let persona = UserPersona.shared
            await CompanionDataTracker.shared.updatePermissions(
                persona.trackingPermissions,
                persona: persona
            )
            await HermesInterestEngine.shared.syncSelectedInterests(for: persona, source: "startup")
            await HermesInterestEngine.shared.scheduleInterestNotifications(for: persona)
            DiagnosticsLog.info("startup", "Companion data tracker booted.")
        }
    }
}

// MARK: - TermsAcceptanceView

private struct TermsAcceptanceView: View {
    let onAccept: () -> Void
    @State private var confirmed = false

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 700
            let sideInset: CGFloat = isWide ? 48 : 20
            let availableWidth = max(320, geometry.size.width - sideInset * 2)
            let contentWidth = isWide ? min(availableWidth, 920) : availableWidth

            ZStack {
                LinearGradient(
                    colors: [Color.BC.background, Color(hex: "#101820"), Color.BC.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: isWide ? 28 : 18) {
                        headerCard(isWide: isWide)

                        legalPreview(
                            title: "Terms of Use",
                            intro: "By using BareClaw, you agree to use it responsibly and understand that companion replies are generated by software.",
                            sections: BareClawLegalContent.termsSections,
                            isWide: isWide
                        )

                        legalPreview(
                            title: "Privacy Policy",
                            intro: "BareClaw is designed to keep personal app data on-device unless you choose to connect outside AI or voice providers.",
                            sections: BareClawLegalContent.privacySections,
                            isWide: isWide
                        )
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, sideInset)
                    .padding(.top, isWide ? 50 : 28)
                    .padding(.bottom, isWide ? 180 : 140)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    acceptBar(isWide: isWide, contentWidth: contentWidth, sideInset: sideInset)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func headerCard(isWide: Bool) -> some View {
        Group {
            if isWide {
                HStack(alignment: .center, spacing: 28) {
                    BearBadgeView(size: 110)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Before BareClaw starts")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundColor(Color.BC.primaryText)
                        Text("Review the Terms of Use and Privacy Policy before setup. BareClaw will not start until these are accepted.")
                            .font(BCFont.body(17))
                            .foregroundColor(Color.BC.secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Text("Required")
                        .bcBadge(Color.BC.accent)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    BearLogoView(size: 56)
                    Text("Before BareClaw starts")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(Color.BC.primaryText)
                    Text("Please review and accept the Terms of Use and Privacy Policy. The app will not start until these are accepted.")
                        .font(BCFont.body(15))
                        .foregroundColor(Color.BC.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(isWide ? 28 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isWide {
                    LinearGradient(
                        colors: [Color.BC.surfaceRaised, Color(hex: "#13251F")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isWide ? 28 : 0))
        .overlay {
            if isWide {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.BC.border, lineWidth: 1)
            }
        }
    }

    private func acceptBar(isWide: Bool, contentWidth: CGFloat, sideInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            Button {
                confirmed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(confirmed ? Color.BC.accent : Color.BC.secondaryText)
                    Text("I have read and agree to the Terms of Use and Privacy Policy.")
                        .font(BCFont.body(isWide ? 15 : 14))
                        .foregroundColor(Color.BC.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAccept) {
                Text("Accept and Continue")
                    .font(BCFont.headline(isWide ? 17 : 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isWide ? 16 : 14)
                    .background(confirmed ? Color.BC.accent : Color.BC.border)
                    .foregroundColor(confirmed ? .black : Color.BC.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!confirmed)
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, sideInset)
        .padding(.top, 16)
        .padding(.bottom, isWide ? 22 : 20)
        .frame(maxWidth: .infinity)
        .background(Color.BC.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.BC.border.opacity(0.8))
                .frame(height: 1)
        }
    }

    private func legalPreview(title: String, intro: String, sections: [LegalSection], isWide: Bool) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: isWide ? 2 : 1
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: isWide ? 26 : 21, weight: .heavy, design: .rounded))
                .foregroundColor(Color.BC.primaryText)
            Text(intro)
                .font(BCFont.body(isWide ? 15 : 14))
                .foregroundColor(Color.BC.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(sections) { section in
                    legalSectionCard(section: section, isWide: isWide)
                }
            }
        }
        .padding(isWide ? 24 : 16)
        .background(Color.BC.surface.opacity(isWide ? 0.92 : 1))
        .clipShape(RoundedRectangle(cornerRadius: isWide ? 24 : 20))
        .overlay(
            RoundedRectangle(cornerRadius: isWide ? 24 : 20)
                .strokeBorder(Color.BC.border, lineWidth: 1)
        )
    }

    private func legalSectionCard(section: LegalSection, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(BCFont.headline(isWide ? 17 : 16))
                .foregroundColor(Color.BC.primaryText)
            Text(section.body)
                .font(BCFont.body(isWide ? 14 : 13))
                .foregroundColor(Color.BC.secondaryText)
                .lineSpacing(isWide ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isWide ? 16 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.BC.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

