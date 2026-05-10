"""SQLite-backed memory store + memory tool tests."""
from __future__ import annotations

from pathlib import Path

import pytest

from genie_swarm.memory import Memory
from genie_swarm.models import ToolCall
from genie_swarm.tools import ToolRegistry
from genie_swarm.tools.base import ToolContext
from genie_swarm.tools.memory import RememberFact, RecallMemory, NoteDecision


# --------------------------------------------------------------------------- #
# Memory store
# --------------------------------------------------------------------------- #

def test_remember_then_recall_round_trips(tmp_path: Path):
    mem = Memory(tmp_path)
    mem.remember("preferred_palette", "muted earth tones", confidence=0.9, source="designer")
    rows = mem.recall("palette")
    assert len(rows) == 1
    assert rows[0].key == "preferred_palette"
    # Fresh fact — decay should be < 1% off the stored confidence.
    assert rows[0].confidence == pytest.approx(0.9, abs=0.01)
    assert rows[0].source == "designer"


def test_recall_decays_old_facts(tmp_path: Path):
    """A fact older than one half-life should come back at ~half confidence."""
    half_life = 1000.0
    mem = Memory(tmp_path, half_life_seconds=half_life)
    mem.remember("style", "monochrome", confidence=1.0)
    fresh = mem.recall("style")[0]
    # Pretend the clock advanced exactly one half-life.
    aged = mem.recall("style", now=fresh.ts + half_life)[0]
    assert aged.confidence == pytest.approx(0.5, abs=0.01)


def test_old_facts_below_threshold_get_pruned(tmp_path: Path):
    half_life = 1.0
    mem = Memory(tmp_path, half_life_seconds=half_life)
    mem.remember("ephemeral", "won't survive", confidence=0.5)
    fresh = mem.recall("ephemeral")[0]
    # ~5 half-lives later, decayed = 0.5 * (0.5)^5 ≈ 0.0156 — below
    # PRUNE_THRESHOLD (0.05) — fact should be gone after the recall.
    aged = mem.recall("ephemeral", now=fresh.ts + 5 * half_life)
    assert aged == []
    # Second recall confirms the row was deleted, not just filtered.
    assert mem.recall("ephemeral", now=fresh.ts + 5 * half_life) == []
    assert mem.all_facts() == []


def test_decay_preserves_relative_ordering(tmp_path: Path):
    """A medium-confidence recent fact should outrank a high-confidence
    much-older one once enough half-lives have elapsed."""
    half_life = 1.0
    mem = Memory(tmp_path, half_life_seconds=half_life)

    # Manually backdate the older fact by 3 half-lives.
    mem.remember("style_pref", "old preference", confidence=1.0)
    older_ts = mem.all_facts()[0].ts
    with mem._conn() as c:
        c.execute("UPDATE facts SET ts=? WHERE key=?", (older_ts - 3 * half_life, "style_pref"))
    mem.remember("style_new", "newer preference", confidence=0.6)

    results = mem.recall("preference")
    older = next(r for r in results if r.key == "style_pref")
    newer = next(r for r in results if r.key == "style_new")
    # Older: 1.0 * 0.5^3 = 0.125.  Newer (fresh): ~0.6.
    assert newer.confidence > older.confidence
    assert results[0].key == "style_new"


def test_remember_overwrites_existing_key(tmp_path: Path):
    mem = Memory(tmp_path)
    mem.remember("style", "minimalist", confidence=0.4, source="a")
    mem.remember("style", "playful", confidence=0.8, source="b")
    rows = mem.recall("style")
    assert len(rows) == 1
    assert rows[0].value == "playful"
    assert rows[0].source == "b"


def test_forget_removes_fact(tmp_path: Path):
    mem = Memory(tmp_path)
    mem.remember("k", "v")
    assert mem.recall("k")
    mem.forget("k")
    assert mem.recall("k") == []


def test_record_project_then_recent(tmp_path: Path):
    mem = Memory(tmp_path)
    mem.record_project("job_a", "TideRider", {"prompt": "..."}, True, "shipped")
    mem.record_project("job_b", "Habitica", {"prompt": "..."}, False, "compile failed")
    recent = mem.recent_projects()
    titles = {p.title for p in recent}
    assert {"TideRider", "Habitica"} == titles


def test_decisions_are_scoped_per_job(tmp_path: Path):
    mem = Memory(tmp_path)
    mem.note_decision("j1", "use SwiftUI?", "yes")
    mem.note_decision("j2", "use SwiftUI?", "yes (with UIKit fallback)")
    j1 = mem.decisions_for("j1")
    j2 = mem.decisions_for("j2")
    assert len(j1) == 1 and len(j2) == 1
    assert j1[0].decision != j2[0].decision


def test_briefing_renders_when_facts_exist(tmp_path: Path):
    mem = Memory(tmp_path)
    mem.remember("preferred_palette", "muted earth tones")
    mem.record_project("j", "Calmly", {"prompt": "x"}, True, "shipped to TestFlight")
    text = mem.briefing()
    assert "preferred_palette" in text
    assert "Calmly" in text
    assert "✓" in text


def test_briefing_empty_when_nothing_stored(tmp_path: Path):
    mem = Memory(tmp_path)
    assert mem.briefing() == ""


# --------------------------------------------------------------------------- #
# Memory tools
# --------------------------------------------------------------------------- #

@pytest.fixture
def memory_registry() -> ToolRegistry:
    r = ToolRegistry()
    for tool in (RememberFact(), RecallMemory(), NoteDecision()):
        r.register(tool)
    return r


@pytest.mark.asyncio
async def test_remember_then_recall_via_tools(memory_registry, sandbox, tmp_path):
    ctx = ToolContext(job_id="j", agent="tester", workspace=str(sandbox.policy.workspace))

    await memory_registry.invoke(
        ToolCall(name="remember_fact", arguments={
            "key": "preferred_palette",
            "value": "muted earth tones",
            "confidence": 0.85,
        }), sandbox, ctx,
    )
    result = await memory_registry.invoke(
        ToolCall(name="recall_memory", arguments={"query": "palette"}),
        sandbox, ctx,
    )
    assert result.ok
    assert "preferred_palette" in result.content
    assert "muted earth tones" in result.content


@pytest.mark.asyncio
async def test_remember_fact_validates_arguments(memory_registry, sandbox):
    ctx = ToolContext(job_id="j", agent="tester", workspace=str(sandbox.policy.workspace))
    result = await memory_registry.invoke(
        ToolCall(name="remember_fact", arguments={"key": "x"}),  # missing value
        sandbox, ctx,
    )
    assert not result.ok
    assert result.metadata.get("kind") == "schema_violation"


@pytest.mark.asyncio
async def test_note_decision_persists(memory_registry, sandbox, tmp_path):
    ctx = ToolContext(job_id="j42", agent="tester", workspace=str(sandbox.policy.workspace))
    result = await memory_registry.invoke(
        ToolCall(name="note_decision", arguments={
            "context": "third-party SDKs?",
            "decision": "no analytics in v1",
        }), sandbox, ctx,
    )
    assert result.ok

    mem = Memory(Path(ctx.workspace).parent)
    decisions = mem.decisions_for("j42")
    assert len(decisions) == 1
    assert "analytics" in decisions[0].decision
