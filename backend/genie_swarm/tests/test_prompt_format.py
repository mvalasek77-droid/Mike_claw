"""Tests for the deterministic provider-tuned prompt formatter."""
from __future__ import annotations

from genie_swarm.models import AppSpec
from genie_swarm.prompt_format import (
    CLAUDE,
    GPT,
    format_app_prompt,
    provider_for_model,
)


def _spec(**kw) -> AppSpec:
    base = dict(title="Habit Hero", prompt="a habit tracker that nags me each morning")
    base.update(kw)
    return AppSpec(**base)


def test_provider_mapping():
    assert provider_for_model("gpt-5") == GPT
    assert provider_for_model("gpt-5-mini") == GPT
    assert provider_for_model("o3-mini") == GPT
    assert provider_for_model("claude-opus-4-7") == CLAUDE
    assert provider_for_model("claude-fable-5") == CLAUDE
    assert provider_for_model("something-unknown") == CLAUDE   # safe default


def test_claude_shape_uses_xml_tags():
    out = format_app_prompt(_spec(features=["streak counter", "morning reminder"]), CLAUDE)
    for tag in ("<task>", "</task>", "<requirements>", "<constraints>", "<deliverable>"):
        assert tag in out
    assert "# Build:" not in out                       # not the GPT shape
    assert "Habit Hero" in out
    assert "habit tracker that nags me each morning." in out
    assert "streak counter." in out                    # feature carried + punctuated


def test_gpt_shape_uses_markdown_numbered():
    out = format_app_prompt(_spec(features=["streak counter"]), GPT)
    assert out.startswith("# Build: Habit Hero")
    assert "## Requirements" in out
    assert "## Constraints" in out
    assert "## Deliverable" in out
    assert "<task>" not in out                          # not the Claude shape
    assert "1. a habit tracker that nags me each morning." in out
    assert "2. streak counter." in out


def test_substance_is_identical_across_providers():
    """Only the SHAPE differs — every requirement and constraint appears
    in both, so switching provider never drops information."""
    spec = _spec(features=["offline mode", "iCloud sync"])
    claude = format_app_prompt(spec, CLAUDE)
    gpt = format_app_prompt(spec, GPT)
    for fragment in (
        "habit tracker that nags me each morning.",
        "offline mode.",
        "iCloud sync.",
        "Persist user data locally",
        "Human Interface Guidelines",
        f"Target iOS {spec.target_ios}",
        spec.style,
        spec.category,
    ):
        assert fragment in claude, fragment
        assert fragment in gpt, fragment


def test_baseline_quality_bar_always_present():
    """Even a one-word description gets the empty/loading/error + first-run
    + persistence requirements injected."""
    out = format_app_prompt(AppSpec(title="X", prompt="calculator"), CLAUDE)
    assert "first-run experience" in out
    assert "empty, loading, and error states" in out
    assert "Persist user data locally" in out


def test_whitespace_is_collapsed():
    messy = AppSpec(title="  Notes  ", prompt="a\n\n  notes   app\twith   tags")
    out = format_app_prompt(messy, GPT)
    assert "a notes app with tags." in out
    assert "  Notes  " not in out                       # title trimmed
    assert "Build: Notes" in out


def test_empty_prompt_still_produces_valid_brief():
    out = format_app_prompt(AppSpec(title="Blank", prompt=""), CLAUDE)
    # No crash, tags intact, baseline requirements still present.
    assert "<requirements>" in out
    assert "first-run experience" in out


# --------------------------------------------------------------------------- #
# /format-prompt route — the live preview the iOS describe-app screen calls.
# --------------------------------------------------------------------------- #

from fastapi import FastAPI
from fastapi.testclient import TestClient

from genie_swarm.api import router


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(router)
    return app


def test_format_prompt_route_returns_both_shapes():
    client = TestClient(_client())
    r = client.post(
        "/api/coding/swarm/format-prompt",
        json={"spec": {"title": "Habit Hero", "prompt": "track habits",
                       "features": ["streaks"]}, "model_id": "gpt-5"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["selected_provider"] == "openai"
    assert body["formatted"].startswith("# Build: Habit Hero")   # matches model_id
    assert body["formatted"] == body["openai"]
    assert "<task>" in body["anthropic"]                          # other shape also returned


def test_format_prompt_route_defaults_to_claude_without_model():
    client = TestClient(_client())
    r = client.post(
        "/api/coding/swarm/format-prompt",
        json={"spec": {"title": "Notes", "prompt": "a notes app"}},
    )
    assert r.status_code == 200
    assert r.json()["selected_provider"] == "anthropic"


def test_format_prompt_route_rejects_invalid_spec():
    client = TestClient(_client())
    r = client.post("/api/coding/swarm/format-prompt", json={"spec": {"prompt": "no title"}})
    assert r.status_code == 400
