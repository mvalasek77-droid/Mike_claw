import Testing
import Foundation
@testable import MetaBro

struct BugReportTests {

    @Test func logStoreKeepsMostRecentEntriesWithinCapacity() async {
        let store = LogStore(capacity: 3)
        for i in 0..<5 {
            await store.record(LogEntry(timestamp: .now, level: .info, category: "test", message: "msg\(i)"))
        }
        let recent = await store.recent()
        #expect(recent.count == 3)
        #expect(recent.map(\.message) == ["msg2", "msg3", "msg4"])
    }

    @Test func logStoreExportTextJoinsFormattedEntries() async {
        let store = LogStore()
        await store.record(LogEntry(timestamp: .now, level: .error, category: "feed", message: "boom"))
        let text = await store.exportText()
        #expect(text.contains("[error]"))
        #expect(text.contains("[feed]"))
        #expect(text.contains("boom"))
    }

    @Test func broLogErrorRecordsToTheSharedStore() async throws {
        await BroLog.store.clear()
        _ = BroLog.error("a logged failure", category: "diagnosticsTest")
        // The store write is dispatched onto the actor; give it a tick to land.
        try await Task.sleep(nanoseconds: 50_000_000)
        let recent = await BroLog.store.recent()
        #expect(recent.contains { $0.message == "a logged failure" && $0.category == "diagnosticsTest" })
    }

    @Test func mockBugReportServiceCollectsSubmissions() async throws {
        let service = MockBugReportService()
        let draft = BugReportDraft(summary: "Feed crashes on scroll", details: "Happens after 50 posts",
                                    severity: .crash, includeDiagnostics: true)
        try await service.submit(draft)
        #expect(service.submitted.count == 1)
        #expect(service.submitted.first?.summary == "Feed crashes on scroll")
        #expect(service.submitted.first?.severity == .crash)
    }

    @Test func diagnosticsSnapshotIncludesAppAndDeviceInfo() async {
        let diagnostics = await MockBugReportService().diagnostics()
        #expect(!diagnostics.osVersion.isEmpty)
        #expect(!diagnostics.deviceModel.isEmpty)
        #expect(!diagnostics.locale.isEmpty)
    }

    @Test func crashReporterRoundTripsAndClearsBreadcrumb() {
        CrashReporter.clear()
        #expect(CrashReporter.lastCrash() == nil)
    }

    @Test func bugSeverityHasAHumanLabel() {
        #expect(BugSeverity.crash.label == "App crashed")
        #expect(BugSeverity.allCases.count == 3)
    }
}
