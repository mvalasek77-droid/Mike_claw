# Claude Prompt Coach — CodeGenie test build

This is the test artifact for the sample prompt in
`docs/SAMPLE_PROMPT_CLAUDE_COACH.md`: the app CodeGenie's swarm is asked
to build, authored end-to-end as the reference for what a real build
should produce. Fully on-device — no account, no server, no network.

## Run it on your Mac

1. `git pull` on branch `claude/copy-tweaks`
2. `open samples/ClaudePromptCoach/ClaudePromptCoach.xcodeproj`
3. Pick any iPhone simulator (iOS 17+) and press **Run**

Bundle id `com.codegenie.claudepromptcoach`, deployment target iOS 17.0,
iPhone-only, dark mode by default.

## Spec → implementation map

| Spec feature | Where it lives |
|---|---|
| New Coach Session: one-sentence goal → 3-5 interview questions → drafted Skill | `CoachSessionView.swift` (flow) + `CoachEngine.swift` (question selection & draft assembly) |
| Four coaching modes as pills (Interview me / Spec first / Launch sub-agents / Verify before you build) | `Models.swift` (`CoachMode`) + `Components.swift` (`ModePillRow`) — each mode changes the question set and output shape in `CoachEngine.swift` |
| Library tab: cards with title, one-liner, times used, heat trail | `LibraryView.swift` + `Components.swift` (`SkillCardView`, `HeatTrailView`) |
| Skill detail with Chain button (compose, don't clone) | `SkillDetailView.swift` + `ChainView.swift` |
| Five starter Skills | `SkillStore.swift` (`starterSkills()`) |
| "Should we capture what we learned?" + visible changelog, never silent | `SkillDetailView.swift` (capture alert) + `SkillStore.evolve` (changelog entry, heartbeat `lastEvolvedAt`) |
| Taste Test before saving (2 yes/no questions → Skill or one-off note) | `Components.swift` (`TasteTestSheet`) wired in `DraftReviewView.swift` |
| Warm neutral + single pulsing accent, glass cards, haptic on save | `Theme.swift` (palette, `AccentPulseModifier`, `Haptics`) |
| Everything on-device, JSON persistence | `SkillStore.swift` (Codable JSON in Documents) |

## Honest note on the coach

CodeGenie's real builds wire the coach to an LLM. This reference build
implements the coach as a deterministic on-device rules engine
(`CoachEngine.swift`): question templates chosen by mode + goal
keywords, and the Skill draft assembled from the user's own answers.
That matches the spec's "everything on-device" constraint and needs no
key — swap `CoachEngine` for a model-backed engine to make the
questions adaptive.
