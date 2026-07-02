"""Live E2E harness: boots the real FastAPI app with a scripted LLM and
drives it exactly like the iOS SwarmClient for the Claude Prompt Coach build."""
from __future__ import annotations

import asyncio
import json
import sys
import traceback
from collections import Counter
from pathlib import Path

sys.path.insert(0, "/home/user/Mike_claw/backend")

import httpx
import uvicorn
from fastapi import FastAPI

from genie_swarm.api import router, state
from genie_swarm.llm import LLMClient, LLMResponse
from genie_swarm.models import ToolCall
from genie_swarm.orchestrator import SwarmConfig

SCRATCH = Path("/tmp/claude-0/-home-user-Mike-claw/601b189d-da0a-5251-b7b3-4875886ebf71/scratchpad")
WS_ROOT = SCRATCH / "coach-ws"
BASE = "/api/coding/swarm"
PORT = 8971

# ---------------------------------------------------------------- app files

PLAN_JSON = json.dumps({
    "app": "Claude Prompt Coach",
    "bundle_id": "com.codegenie.claudepromptcoach",
    "tabs": ["Coach", "Library"],
    "modes": ["Interview me", "Spec first", "Launch sub-agents", "Verify before you build"],
    "models": ["Skill", "CoachSession", "TasteTestResult"],
    "starter_skills": ["Draft Email", "Debug This Code", "Write PR Description",
                        "Interview Me", "Build A Skill From Our Chat"],
    "files": ["ClaudePromptCoach/Models/Skill.swift",
              "ClaudePromptCoach/Stores/SkillStore.swift",
              "ClaudePromptCoach/Coach/CoachEngine.swift",
              "ClaudePromptCoach/Views/CoachSessionView.swift",
              "ClaudePromptCoach/Views/LibraryView.swift",
              "ClaudePromptCoach/Views/TasteTestView.swift",
              "ClaudePromptCoach/ClaudePromptCoachApp.swift"],
}, indent=2)

PLAN_MD = """# Claude Prompt Coach — build plan

Two-tab SwiftUI app (iOS 17+, Liquid Glass, dark-mode default, fully on-device).

- **Coach tab**: New Coach Session -> one-sentence goal -> 3-5 interview
  questions -> drafted Skill (description, step-by-step instructions, optional tools).
  Four modes as pill buttons: Interview me / Spec first / Launch sub-agents /
  Verify before you build.
- **Library tab**: saved Skill cards (title, one-liner, usage count, heat trail),
  Chain button to compose skills, heart-beat indicator when a skill evolved.
- After-session capture dialog: "Should we capture what we learned?" -> updates
  the used Skill, never silently.
- Taste Test gate before save: >3 uses? better than manual? else save as one-off note.
- Storage: on-device JSON via SkillStore; no network, no account.
"""

SKILL_SWIFT = """import Foundation

/// A reusable Claude Skill: not a one-shot prompt but a titled description,
/// step-by-step instructions, and optional attached tools.
struct Skill: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var summary: String
    var instructions: [String]
    var tools: [String] = []
    var usageCount: Int = 0
    var updatedAt: [Date] = []          // heat trail
    var evolved: Bool = false           // heart-beat indicator
    var chainedWith: [UUID] = []

    mutating func capture(learning: String) {
        instructions.append(learning)
        updatedAt.append(Date())
        evolved = true                  // never modify a Skill silently
    }
}

enum CoachMode: String, CaseIterable, Identifiable, Codable {
    case interviewMe = "Interview me"
    case specFirst = "Spec first"
    case launchSubAgents = "Launch sub-agents"
    case verifyBeforeBuild = "Verify before you build"
    var id: String { rawValue }
}

struct TasteTest: Codable {
    var willUseThreeTimes: Bool
    var betterThanManual: Bool
    var shouldBeSkill: Bool { willUseThreeTimes && betterThanManual }
}
"""

SKILLSTORE_SWIFT = """import Foundation
import Combine

/// On-device store. The user's prompts are theirs and never leave the phone.
@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [Skill] = []
    @Published private(set) var oneOffNotes: [String] = []

    private let url = FileManager.default.urls(for: .documentDirectory,
                                               in: .userDomainMask)[0]
        .appendingPathComponent("skills.json")

    init() { load(); if skills.isEmpty { seedStarterLibrary() } }

    func seedStarterLibrary() {
        skills = [
            Skill(title: "Draft Email", summary: "Turn bullet points into a sendable email",
                  instructions: ["Ask for audience and tone", "Draft, then tighten to 120 words"]),
            Skill(title: "Debug This Code", summary: "Structured root-cause hunt",
                  instructions: ["Reproduce first", "Bisect the diff", "Verify the fix with a test"]),
            Skill(title: "Write PR Description", summary: "Summarise a diff for reviewers",
                  instructions: ["List user-visible changes", "Call out risk and test evidence"]),
            Skill(title: "Interview Me", summary: "Flip the script: Claude asks 3-5 questions first",
                  instructions: ["Ask goal, audience, acceptance test, edge cases", "Then draft"]),
            Skill(title: "Build A Skill From Our Chat", summary: "Distill this session into a Skill",
                  instructions: ["Extract steps that worked", "Run the Taste Test before saving"]),
        ]
        save()
    }

    func save(_ skill: Skill, tasteTest: TasteTest) {
        if tasteTest.shouldBeSkill {
            skills.append(skill)
        } else {
            oneOffNotes.append(skill.title + ": " + skill.summary)
        }
        save()
    }

    func recordUse(of id: UUID) {
        guard let i = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[i].usageCount += 1
        save()
    }

    func capture(learning: String, into id: UUID) {
        guard let i = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[i].capture(learning: learning)   // asks the user first, never silent
        save()
    }

    func chain(_ a: UUID, with b: UUID) {
        guard let i = skills.firstIndex(where: { $0.id == a }) else { return }
        skills[i].chainedWith.append(b)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Skill].self, from: data) else { return }
        skills = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(skills) { try? data.write(to: url) }
    }
}
"""

COACHENGINE_SWIFT = """import Foundation

/// Drives one coaching session: interview -> draft Skill.
struct CoachEngine {
    /// 3-5 targeted questions to fill gaps before drafting.
    func interviewQuestions(for goal: String) -> [String] {
        [
            "What outcome makes this a success (acceptance test)?",
            "Who is the audience for the output?",
            "What edge cases have bitten you before?",
            "Should the output be reviewed before it's used anywhere real?",
        ]
    }

    func draftSkill(goal: String, answers: [String], mode: CoachMode) -> Skill {
        var steps: [String]
        switch mode {
        case .interviewMe:
            steps = ["Restate the goal", "Apply the interview answers", "Draft, then self-critique"]
        case .specFirst:
            steps = ["Write a short spec resolving ambiguity on paper",
                     "Get a yes on the spec", "Only then draft the prompt"]
        case .launchSubAgents:
            steps = ["Split into 3-5 parallel sub-agent prompts",
                     "Run them independently", "Synthesise with a final combiner prompt"]
        case .verifyBeforeBuild:
            steps = ["Draft the prompt", "Append a verification checklist",
                     "Validate against the checklist before touching real files or APIs"]
        }
        return Skill(title: goal, summary: "Drafted in \\(mode.rawValue) mode",
                     instructions: steps)
    }
}
"""

SESSIONVIEW_SWIFT = """import SwiftUI

struct CoachSessionView: View {
    @EnvironmentObject var store: SkillStore
    @State private var goal = ""
    @State private var mode: CoachMode = .interviewMe
    @State private var draft: Skill?
    @State private var showCapture = false
    @State private var showTasteTest = false
    private let engine = CoachEngine()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("What are you trying to do? One sentence.", text: $goal)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Session goal")
                // Four coaching modes as pill buttons.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(CoachMode.allCases) { m in
                            Button(m.rawValue) { mode = m }
                                .buttonStyle(.borderedProminent)
                                .tint(mode == m ? .accentColor : .secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
                Button("New Coach Session") {
                    let qs = engine.interviewQuestions(for: goal)
                    draft = engine.draftSkill(goal: goal, answers: qs, mode: mode)
                    showTasteTest = true
                }
                .disabled(goal.isEmpty)
                if let draft { SkillDetailCard(skill: draft) }
            }
            .padding()
            .navigationTitle("Coach")
            .sensoryFeedback(.success, trigger: showTasteTest) // haptic on save
            .sheet(isPresented: $showTasteTest) {
                if let draft { TasteTestView(skill: draft) }
            }
            .alert("Should we capture what we learned?", isPresented: $showCapture) {
                Button("Update the Skill") {
                    if let d = draft { store.capture(learning: "Session insight", into: d.id) }
                }
                Button("Not this time", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark) // dark mode by default
    }
}

struct SkillDetailCard: View {
    let skill: Skill
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.title).font(.headline)
            Text(skill.summary).font(.subheadline).foregroundStyle(.secondary)
            ForEach(skill.instructions, id: \\.self) { Text("• " + $0).font(.caption) }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) // Liquid Glass
    }
}
"""

LIBRARYVIEW_SWIFT = """import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: SkillStore
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            List(store.skills) { skill in
                NavigationLink(value: skill) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(skill.title).font(.headline)
                            if skill.evolved {
                                Image(systemName: "heart.fill")   // heart-beat: skill evolved
                                    .foregroundStyle(.pink)
                                    .scaleEffect(pulse ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: pulse)
                            }
                        }
                        Text(skill.summary).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Text("Used \\(skill.usageCount)x").font(.caption2)
                            HeatTrail(dates: skill.updatedAt)   // when it was updated
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Skill.self) { skill in
                SkillDetail(skill: skill)
            }
            .onAppear { pulse = true }
        }
        .preferredColorScheme(.dark)
    }
}

struct HeatTrail: View {
    let dates: [Date]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(dates.count, 12), id: \\.self) { _ in
                Circle().fill(.orange).frame(width: 4, height: 4)
            }
        }
        .accessibilityLabel("Updated \\(dates.count) times")
    }
}

struct SkillDetail: View {
    @EnvironmentObject var store: SkillStore
    let skill: Skill
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(skill.summary)
                ForEach(skill.instructions, id: \\.self) { Text("• " + $0) }
                if !skill.tools.isEmpty { Text("Tools: " + skill.tools.joined(separator: ", ")) }
                Button("Chain with another Skill") {
                    if let other = store.skills.first(where: { $0.id != skill.id }) {
                        store.chain(skill.id, with: other.id)   // compose, don't clone
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(skill.title)
    }
}
"""

TASTETEST_SWIFT = """import SwiftUI

/// Lightweight "Should this be a Skill or a one-off?" gate before saving.
struct TasteTestView: View {
    @EnvironmentObject var store: SkillStore
    @Environment(\\.dismiss) private var dismiss
    let skill: Skill
    @State private var q1 = false
    @State private var q2 = false

    var body: some View {
        Form {
            Section("The taste test") {
                Toggle("Will you use this more than 3 times?", isOn: $q1)
                Toggle("Would the output beat the last five manual runs?", isOn: $q2)
            }
            Button(q1 && q2 ? "Save as Skill" : "Save as one-off note") {
                store.save(skill, tasteTest: TasteTest(willUseThreeTimes: q1,
                                                       betterThanManual: q2))
                dismiss()
            }
        }
        .presentationDetents([.medium])
    }
}
"""

APP_SWIFT = """import SwiftUI

@main
struct ClaudePromptCoachApp: App {
    @StateObject private var store = SkillStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                CoachSessionView()
                    .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical") }
            }
            .environmentObject(store)
            .tint(Color("WarmAccent"))          // warm neutral palette, single accent
            .preferredColorScheme(.dark)        // dark mode by default
        }
    }
}
"""

UNIT_TESTS_SWIFT = """import XCTest
@testable import ClaudePromptCoach

final class SkillStoreTests: XCTestCase {
    @MainActor func testStarterLibraryHasFiveSkills() {
        let store = SkillStore()
        XCTAssertEqual(store.skills.count, 5)
        XCTAssertTrue(store.skills.contains { $0.title == "Interview Me" })
    }

    @MainActor func testTasteTestGateRoutesOneOffs() {
        let store = SkillStore()
        let before = store.skills.count
        store.save(Skill(title: "Junk", summary: "", instructions: []),
                   tasteTest: TasteTest(willUseThreeTimes: false, betterThanManual: true))
        XCTAssertEqual(store.skills.count, before)      // rejected -> one-off note
        XCTAssertEqual(store.oneOffNotes.count, 1)
    }

    func testCaptureMarksSkillEvolved() {
        var s = Skill(title: "T", summary: "", instructions: [])
        s.capture(learning: "new edge case")
        XCTAssertTrue(s.evolved)
        XCTAssertEqual(s.updatedAt.count, 1)
    }

    func testDraftSkillModes() {
        let engine = CoachEngine()
        for mode in CoachMode.allCases {
            let s = engine.draftSkill(goal: "g", answers: [], mode: mode)
            XCTAssertFalse(s.instructions.isEmpty)
        }
        XCTAssertEqual(engine.interviewQuestions(for: "g").count, 4)
    }
}
"""

UI_TESTS_SWIFT = """import XCTest

final class CoachFlowUITests: XCTestCase {
    func testGoldenPathNewSessionToLibrary() {
        let app = XCUIApplication()
        app.launch()
        app.textFields["Session goal"].tap()
        app.textFields["Session goal"].typeText("Write better PR descriptions")
        app.buttons["Spec first"].tap()
        app.buttons["New Coach Session"].tap()
        XCTAssertTrue(app.staticTexts["The taste test"].waitForExistence(timeout: 2))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Draft Email"].exists)
    }
}
"""

AGENT_FILES: dict[str, list[tuple[str, str]]] = {
    "architect": [("docs/PLAN.md", PLAN_MD), ("docs/plan.json", PLAN_JSON)],
    "coder": [("ClaudePromptCoach/Models/Skill.swift", SKILL_SWIFT),
              ("ClaudePromptCoach/Stores/SkillStore.swift", SKILLSTORE_SWIFT),
              ("ClaudePromptCoach/Coach/CoachEngine.swift", COACHENGINE_SWIFT)],
    "designer": [("ClaudePromptCoach/Views/CoachSessionView.swift", SESSIONVIEW_SWIFT),
                 ("ClaudePromptCoach/Views/LibraryView.swift", LIBRARYVIEW_SWIFT),
                 ("ClaudePromptCoach/Views/TasteTestView.swift", TASTETEST_SWIFT)],
    "integrator": [("ClaudePromptCoach/ClaudePromptCoachApp.swift", APP_SWIFT)],
    "unit_tester": [("Tests/SkillStoreTests.swift", UNIT_TESTS_SWIFT)],
    "ui_tester": [("UITests/CoachFlowUITests.swift", UI_TESTS_SWIFT)],
}

FINISH_TEXT = {
    "architect": "Plan written: docs/PLAN.md and docs/plan.json cover both tabs, four modes, and the 5-skill starter library.",
    "coder": "Implemented Skill model, SkillStore with starter library + taste-test gate, and CoachEngine with all four modes.",
    "designer": "All SwiftUI views implemented with Liquid Glass materials, dark mode default, accessibility labels, and the capture dialog.",
    "integrator": "App entry point wired: TabView with Coach + Library, shared SkillStore, warm accent. swift build succeeds.",
    "unit_tester": "Ran xcodebuild test: all tests pass — 4 passed, 0 failures.",
    "ui_tester": "XCUITest golden path written; simctl screenshots captured; all green.",
    "reviewer": "Reviewed the diff and ran swiftlint: [] — no blocking findings.",
    "security": "Audit clean: no hard-coded keys, everything on-device, no network calls, ATS untouched.",
}


def classify(prompt: str) -> str:
    p = prompt.lower()
    if "plan the xcode project" in p: return "architect"
    if "implement every swift file" in p or "unit tester reported failures" in p: return "coder"
    if "implement every swiftui view" in p: return "designer"
    if "glue the project together" in p or "re-glue" in p: return "integrator"
    if "xctest coverage" in p: return "unit_tester"
    if "drive simctl" in p: return "ui_tester"
    if "review the diff" in p: return "reviewer"
    if "audit for keys" in p: return "security"
    return "reviewer"


class CoachScriptedLLM(LLMClient):
    """Deterministic, content-aware fake. Keyed on the current agent's
    user prompt so parallel build/test layers stay deterministic."""

    def __init__(self) -> None:
        self.gate = asyncio.Event()
        self.gate.set()
        self.delay = 0.05
        self.calls = 0

    async def complete(self, **kwargs) -> LLMResponse:
        self.calls += 1
        await self.gate.wait()
        await asyncio.sleep(self.delay)
        msgs = kwargs["messages"]
        last_user = next(m for m in reversed(msgs) if m.role == "user")
        agent = classify(last_user.content)
        usage = {"input_tokens": 1500, "output_tokens": 600}
        if msgs and msgs[-1].role == "tool":
            return LLMResponse(text=FINISH_TEXT[agent], tool_calls=[],
                               stop_reason="end_turn", usage=usage)
        files = AGENT_FILES.get(agent)
        if files:
            return LLMResponse(
                text=f"Writing {len(files)} file(s) for {agent}.",
                tool_calls=[ToolCall(name="write_file", arguments={"path": p, "body": b})
                            for p, b in files],
                stop_reason="tool_use", usage=usage)
        return LLMResponse(text=FINISH_TEXT[agent], tool_calls=[],
                           stop_reason="end_turn", usage=usage)


SPEC = {
    "title": "Claude Prompt Coach",
    "prompt": ("An iPhone app that turns rough prompts into hyper-focused, reusable Claude "
               "Skills: the coach interviews the user with 3-5 questions, then drafts a Skill "
               "with a description, step-by-step instructions, and optional tools. Four coaching "
               "modes (Interview me, Spec first, Launch sub-agents, Verify before you build), a "
               "Library tab with five starter Skills, skill chaining, after-session capture, and "
               "a Taste Test gate before saving. iOS 26 Liquid Glass, dark mode by default, "
               "fully on-device."),
    "category": "productivity",
    "style": "liquidGlass",
    "target_ios": "17.0",
    "features": [
        "Interview me — coach asks 3-5 targeted questions before drafting",
        "Draft as a Skill — description + step-by-step instructions + optional tools",
        "Spec first — produce a short spec doc before the prompt",
        "Launch sub-agents — split complex asks into parallel prompts plus a synth prompt",
        "Verify before you build — appended verification checklist for high-risk steps",
        "Compose don't clone — chain small Skills instead of one giant prompt",
        "Skills get smarter — after-session capture updates the Skill, never silently",
        "The taste test — Skill-or-one-off gate before saving",
    ],
}

BUILD_BODY = {
    "spec": SPEC,
    "parallel": True,
    "skip_tests": False,
    "auth_mode": "codegenie",
    "preferred_model": "claude-sonnet-4-6",
    "billing_plan": "free",
    "model_overrides": {r: "claude-sonnet-4-6" for r in
                        ("architect", "coder", "designer", "integrator",
                         "unit_tester", "ui_tester", "reviewer", "security")},
    "cost_cap_usd": 5,
}

RESULTS: list[tuple[str, str, str]] = []


def report(stage: str, ok: bool, evidence: str) -> None:
    RESULTS.append((stage, "PASS" if ok else "FAIL", evidence))
    print(f"[{'PASS' if ok else 'FAIL'}] {stage}: {evidence}", flush=True)


async def sse_reader(client: httpx.AsyncClient, job_id: str, events: list[dict],
                     attached: asyncio.Event) -> None:
    try:
        async with client.stream("GET", f"{BASE}/{job_id}/stream",
                                 timeout=httpx.Timeout(10, read=60)) as r:
            attached.set()
            async for line in r.aiter_lines():
                if line.startswith("data: "):
                    ev = json.loads(line[6:])
                    events.append(ev)
                    if ev["type"] == "done":
                        return
    except Exception as exc:
        events.append({"type": "_reader_error", "payload": {"err": repr(exc)}})
        attached.set()


async def wait_state(client, job_id, targets: set[str], timeout=30.0) -> str:
    end = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < end:
        r = await client.get(f"{BASE}/{job_id}/status")
        if r.status_code == 200 and r.json()["state"] in targets:
            return r.json()["state"]
        await asyncio.sleep(0.1)
    return "(timeout)"


async def main() -> None:
    llm = CoachScriptedLLM()
    state.llm = llm
    state.config = SwarmConfig(workspace_root=WS_ROOT)
    WS_ROOT.mkdir(parents=True, exist_ok=True)

    app = FastAPI()
    app.include_router(router)
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT,
                                           log_level="warning"))
    server_task = asyncio.create_task(server.serve())
    await asyncio.sleep(0.5)

    async with httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}",
                                 timeout=30.0) as client:
        # ---------------- a. POST /build ----------------
        try:
            llm.gate.clear()
            r = await client.post(f"{BASE}/build", json=BUILD_BODY)
            job1 = r.json().get("job_id", "")
            report("a. POST /build", r.status_code == 200 and job1.startswith("job_"),
                   f"HTTP {r.status_code}, job_id={job1}, state={r.json().get('state')}")
        except Exception:
            traceback.print_exc()
            report("a. POST /build", False, "exception during build POST")
            return

        # ---------------- b. SSE stream ----------------
        events: list[dict] = []
        attached = asyncio.Event()
        reader = asyncio.create_task(sse_reader(client, job1, events, attached))
        await asyncio.wait_for(attached.wait(), timeout=10)
        llm.gate.set()
        try:
            await asyncio.wait_for(reader, timeout=60)
        except asyncio.TimeoutError:
            reader.cancel()
        counts = Counter(e["type"] for e in events)
        agents_started = {e.get("agent") for e in events if e["type"] == "agent.started"}
        # NOTE: job.created / job.state(planning) / architect's agent.started are
        # emitted before any SSE subscriber can attach (no replay buffer in
        # EventStream), so a late subscriber never sees them. Assert on what a
        # real attached client can mechanically receive.
        report("b. SSE stream",
               counts.get("done", 0) == 1 and counts.get("agent.finished", 0) >= 8
               and counts.get("cost.update", 0) >= 8 and counts.get("job.state", 0) >= 2
               and counts.get("tool.call", 0) >= 10,
               f"event counts={dict(counts)}; agents={sorted(a or '' for a in agents_started)}")

        # ---------------- c. status until terminal ----------------
        s = await wait_state(client, job1, {"succeeded", "failed", "cancelled"})
        report("c. GET /status terminal", s == "succeeded", f"final state={s}")

        # ---------------- d. GET /files ----------------
        try:
            r = await client.get(f"{BASE}/{job1}/files")
            files = r.json()["files"]
            visible = [f for f in files if not f.startswith(".codegenie")]
            judgements = []
            for path in ("ClaudePromptCoach/Views/CoachSessionView.swift",
                         "ClaudePromptCoach/Stores/SkillStore.swift",
                         "docs/plan.json"):
                fr = await client.get(f"{BASE}/{job1}/file", params={"path": path})
                body = fr.json().get("body", "") if fr.status_code == 200 else ""
                judgements.append(f"{path}: {fr.status_code}, {len(body)} chars")
            report("d. GET /files", len(visible) >= 9,
                   f"{len(visible)} workspace files: {visible}; reads: {judgements}")
        except Exception as exc:
            report("d. GET /files", False, repr(exc))

        # ---------------- e. perfection ----------------
        try:
            r = await client.post(f"{BASE}/{job1}/perfection", json={})
            j = r.json()
            report("e. POST /perfection", r.status_code == 200 and "score" in j,
                   f"HTTP {r.status_code}, score={j.get('score')}, gate={j.get('release_gate')}, "
                   f"probes={j.get('probes_run', j.get('probes'))}, findings={len(j.get('findings', []))}")
        except Exception as exc:
            report("e. POST /perfection", False, repr(exc))

        # ---------------- f. release readiness ----------------
        try:
            r = await client.post(f"{BASE}/{job1}/release-readiness")
            j = r.json()
            nxt = (j.get("next_actions") or ["(none)"])[0]
            report("f. POST /release-readiness", r.status_code == 200 and "release_gate" in j,
                   f"HTTP {r.status_code}, gate={j.get('release_gate')}, score={j.get('score')}, "
                   f"first next_action={nxt!r}")
        except Exception as exc:
            report("f. POST /release-readiness", False, repr(exc))

        # ---------------- g1. snapshot ----------------
        try:
            r = await client.post(f"{BASE}/{job1}/snapshot", json={"label": "post-audit manual"})
            j = r.json()
            report("g1. POST /snapshot", r.status_code == 200 and j.get("ok") is True,
                   f"HTTP {r.status_code}, label={j.get('label')!r}, files={j.get('files')}")
        except Exception as exc:
            report("g1. POST /snapshot", False, repr(exc))

        # ---------------- g2. second build, cancel mid-run ----------------
        try:
            llm.delay = 0.35
            llm.gate.clear()
            r = await client.post(f"{BASE}/build", json=BUILD_BODY)
            job2 = r.json()["job_id"]
            ev2: list[dict] = []
            att2 = asyncio.Event()
            rdr2 = asyncio.create_task(sse_reader(client, job2, ev2, att2))
            await asyncio.wait_for(att2.wait(), timeout=10)
            llm.gate.set()
            # wait until the build layer started (after-architect checkpoint saved)
            deadline = asyncio.get_event_loop().time() + 30
            while asyncio.get_event_loop().time() < deadline:
                if any(e["type"] == "job.state" and e["payload"].get("state") == "building"
                       for e in ev2):
                    break
                await asyncio.sleep(0.05)
            await asyncio.sleep(0.3)   # let Coder/Designer be genuinely mid-flight
            rc = await client.post(f"{BASE}/{job2}/cancel", json={})
            s2 = await wait_state(client, job2, {"cancelled", "failed", "succeeded"})
            try:
                await asyncio.wait_for(rdr2, timeout=10)
            except asyncio.TimeoutError:
                rdr2.cancel()
            done_ev = next((e for e in ev2 if e["type"] == "done"), {})
            report("g2. cancel mid-run", rc.status_code == 200 and s2 == "cancelled",
                   f"cancel HTTP {rc.status_code}, state={s2}, "
                   f"done.reason={done_ev.get('payload', {}).get('reason')}")
        except Exception as exc:
            traceback.print_exc()
            report("g2. cancel mid-run", False, repr(exc))
            job2 = None

        # ---------------- g3. resume with one-run cap override + double-resume guard ----------------
        if job2:
            try:
                llm.delay = 0.3
                ev3: list[dict] = []
                att3 = asyncio.Event()
                rdr3 = asyncio.create_task(sse_reader(client, job2, ev3, att3))
                await asyncio.wait_for(att3.wait(), timeout=10)
                r = await client.post(f"{BASE}/{job2}/resume", json={"cost_cap_usd": 10})
                ok_resume = r.status_code == 200
                r2 = await client.post(f"{BASE}/{job2}/resume", json={"cost_cap_usd": 10})
                guard_409 = r2.status_code == 409
                # Wait for the resume task to actually start (job.state is still
                # "cancelled" until the spawned coroutine runs), then for terminal.
                s_run = await wait_state(client, job2, {"building", "testing",
                                                        "succeeded", "failed"}, timeout=15)
                llm.delay = 0.05
                s3 = await wait_state(client, job2, {"succeeded", "failed", "cancelled"},
                                      timeout=90)
                try:
                    await asyncio.wait_for(rdr3, timeout=30)
                except asyncio.TimeoutError:
                    rdr3.cancel()
                done3 = next((e for e in ev3 if e["type"] == "done"), {})
                fr = await client.get(f"{BASE}/{job2}/files")
                n2 = len([f for f in fr.json()["files"] if not f.startswith(".codegenie")])
                report("g3. resume + cap override", ok_resume and s3 == "succeeded",
                       f"resume HTTP {r.status_code}, ran through state={s_run}, "
                       f"final state={s3}, done payload={done3.get('payload')}, {n2} files")
                report("g4. double-resume guard", guard_409,
                       f"second resume HTTP {r2.status_code}: {r2.json().get('detail')!r}")
            except Exception as exc:
                traceback.print_exc()
                report("g3. resume + cap override", False, repr(exc))
                report("g4. double-resume guard", False, "not reached")

        # ---------------- g5. bogus id 404 ----------------
        r = await client.get(f"{BASE}/job_doesnotexist99/status")
        report("g5. bogus id 404", r.status_code == 404, f"HTTP {r.status_code}")

        print(f"\ntotal scripted LLM calls: {llm.calls}")

    server.should_exit = True
    await asyncio.wait_for(server_task, timeout=5)

    print("\n===== SUMMARY =====")
    for stage, verdict, evidence in RESULTS:
        print(f"{verdict}  {stage} — {evidence}")


if __name__ == "__main__":
    asyncio.run(main())
