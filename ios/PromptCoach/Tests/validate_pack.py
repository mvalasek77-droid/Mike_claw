#!/usr/bin/env python3
"""
Prompt Coach — model pack contract tests.

These run in CI (and on any machine with Python) and enforce the contract
between `model-pack.json` and the Swift code that decodes it. A Linux box
can't compile Swift, so this is the guardrail that catches the failure mode
that would otherwise crash the app on launch: a pack that doesn't match the
decoder.

Run:  python3 ios/PromptCoach/Tests/validate_pack.py
Exit: 0 = all pass, 1 = failures (printed)
"""

from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
APP_PACK = ROOT / "ios/PromptCoach/PromptCoach/Resources/model-pack.json"
DOCS_PACK = ROOT / "docs/model-pack.json"
ENGINE = ROOT / "ios/PromptCoach/PromptCoach/Engine/CoachEngine.swift"
MODELS_SWIFT = ROOT / "ios/PromptCoach/PromptCoach/Models/ModelPack.swift"

failures: list[str] = []
passes: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        passes.append(name)
    else:
        failures.append(f"{name}{': ' + detail if detail else ''}")


# ---------------------------------------------------------------- load

if not APP_PACK.exists():
    print(f"FATAL: bundled pack missing at {APP_PACK}")
    sys.exit(1)

pack = json.loads(APP_PACK.read_text())
check("bundled pack is valid JSON", True)

# The bundled copy must match the docs source of truth, or the app ships
# stale coaching rules while the docs claim otherwise.
if DOCS_PACK.exists():
    check(
        "bundled pack matches docs/model-pack.json",
        json.loads(DOCS_PACK.read_text()) == pack,
        "re-copy docs/model-pack.json into PromptCoach/Resources/",
    )

# ------------------------------------------------- required top-level keys
# Mirrors ModelPack.CodingKeys in ModelPack.swift. A missing key here is a
# decode failure -> fatalError on launch.
REQUIRED_TOP = [
    "pack_version", "cross_model_rules", "efficiency_rules", "techniques",
    "task_playbooks", "refusal_handling", "advanced_features", "models",
    "recommender",
]
for key in REQUIRED_TOP:
    check(f"top-level key '{key}' present", key in pack)

check("pack_version is a non-empty string",
      isinstance(pack.get("pack_version"), str) and bool(pack.get("pack_version")))

# --------------------------------------------------------------- techniques

lib = pack["techniques"]["library"]
tech_ids = {t["id"] for t in lib}
check("technique library non-empty", len(lib) > 0)
for t in lib:
    for k in ("id", "name", "category", "when"):
        check(f"technique '{t.get('id','?')}' has '{k}'", k in t and isinstance(t[k], str))
check("technique ids unique", len(tech_ids) == len(lib))
check("techniques.retired is a list of strings",
      isinstance(pack["techniques"]["retired"], list)
      and all(isinstance(x, str) for x in pack["techniques"]["retired"]))

# --------------------------------------------------------------- models

models = pack["models"]
model_ids = {m["id"] for m in models}
check("models non-empty", len(models) > 0)
check("model ids unique", len(model_ids) == len(models))

# Mirrors ModelProfile.CodingKeys. price_note / default_effort are optional
# in Swift (String?), everything else is non-optional and must be present.
REQUIRED_MODEL = [
    "name", "id", "accent", "price_in_per_mtok", "price_out_per_mtok",
    "one_liner", "temperament", "strengths", "best_fit",
]
for m in models:
    mid = m.get("id", "?")
    for k in REQUIRED_MODEL:
        check(f"model '{mid}' has '{k}'", k in m)
    check(f"model '{mid}' prices are numbers",
          isinstance(m.get("price_in_per_mtok"), (int, float))
          and isinstance(m.get("price_out_per_mtok"), (int, float)))
    check(f"model '{mid}' strengths is a non-empty list",
          isinstance(m.get("strengths"), list) and len(m["strengths"]) > 0)
    # Optional-but-typed fields: if present they must be the right shape.
    if "suppress_techniques" in m:
        check(f"model '{mid}' suppress_techniques is a list of known technique ids",
              isinstance(m["suppress_techniques"], list)
              and all(s in tech_ids for s in m["suppress_techniques"]),
              str([s for s in m.get("suppress_techniques", []) if s not in tech_ids]))
    if "extra_instructions" in m:
        check(f"model '{mid}' extra_instructions is a list of strings",
              isinstance(m["extra_instructions"], list)
              and all(isinstance(s, str) for s in m["extra_instructions"]))
    if "rewrite_rules" in m:
        check(f"model '{mid}' rewrite_rules non-empty",
              isinstance(m["rewrite_rules"], list) and len(m["rewrite_rules"]) > 0)

# Opus 5 must be present — it is the current Opus tier and the app claims
# to cover current models.
check("Claude Opus 5 is in the pack", "claude-opus-5" in model_ids)

# ------------------------------------------------------------- playbooks

playbooks = pack["task_playbooks"]["playbooks"]
check("playbooks non-empty", len(playbooks) > 0)
tasks = [p["task"] for p in playbooks]
check("playbook tasks unique", len(set(tasks)) == len(tasks))
for p in playbooks:
    for k in ("task", "recommend", "techniques", "output"):
        check(f"playbook '{p.get('task','?')}' has '{k}'", k in p)
    check(f"playbook '{p['task']}' recommends a known model",
          p.get("recommend") in model_ids, p.get("recommend", ""))
    unknown = [t for t in p.get("techniques", []) if t not in tech_ids]
    check(f"playbook '{p['task']}' references only known techniques",
          not unknown, str(unknown))

# ------------------------------------------------------------ recommender

rec = pack["recommender"]
for k in ("default", "rules", "tie_breaker"):
    check(f"recommender has '{k}'", k in rec)
check("recommender default is a known model", rec.get("default") in model_ids)
for r in rec.get("rules", []):
    for k in ("model", "when", "why"):
        check(f"recommender rule has '{k}'", k in r)
    check(f"recommender rule model '{r.get('model')}' is known",
          r.get("model") in model_ids)

# ------------------------------------------------- advanced features

af = pack["advanced_features"]
check("advanced_features has features", isinstance(af.get("features"), list) and af["features"])
for f in af["features"]:
    for k in ("id", "name", "what", "how", "when"):
        check(f"feature '{f.get('id','?')}' has '{k}'", k in f)
checklist = af.get("report_card_checklist", [])
for c in checklist:
    for k in ("item", "checks"):
        check(f"report card item has '{k}'", k in c)

# ---------------------------------------- cross-check against Swift source

if ENGINE.exists():
    engine_src = ENGINE.read_text()

    # The engine's report-card switch must handle exactly the pack's items,
    # or an item silently scores false forever (default: return false).
    engine_items = set(re.findall(r'case "([a-z_]+)": return', engine_src))
    pack_items = {c["item"] for c in checklist}
    missing_in_engine = pack_items - engine_items
    check("engine scores every report-card item in the pack",
          not missing_in_engine, f"unscored: {sorted(missing_in_engine)}")

    # Every TaskType case must have a playbook, else detection falls through
    # to a nil playbook and the recommender default.
    m = re.search(r"enum TaskType[^{]*\{\s*case ([^\n]+)", engine_src)
    if m:
        swift_tasks = {c.strip() for c in m.group(1).split(",")}
        missing_pb = swift_tasks - set(tasks)
        check("every Swift TaskType has a playbook",
              not missing_pb, f"missing playbooks: {sorted(missing_pb)}")

    # Model ids the engine hardcodes (tints etc.) should exist in the pack.
    hardcoded = set(re.findall(r'"(claude-[a-z0-9.\-]+)"', engine_src))
    unknown_hardcoded = hardcoded - model_ids
    check("engine hardcodes no unknown model ids",
          not unknown_hardcoded, str(sorted(unknown_hardcoded)))

GLASS = ROOT / "ios/PromptCoach/PromptCoach/Theme/Glass.swift"
if GLASS.exists():
    glass_src = GLASS.read_text()
    # Every model in the pack needs a tint, or its chip/background falls back
    # to the generic accent and the per-model re-tint silently breaks.
    tinted = set(re.findall(r'case "(claude-[a-z0-9.\-]+)":\s*return Color', glass_src))
    missing_tint = model_ids - tinted
    check("every model has a Glass tint", not missing_tint,
          f"untinted: {sorted(missing_tint)}")
    stale_tint = tinted - model_ids
    check("no Glass tints for models absent from the pack", not stale_tint,
          f"stale: {sorted(stale_tint)}")

if ENGINE.exists():
    # The engine must actually consult suppress_techniques, or per-model
    # behavioral differences (Opus 5's self-verification) are ignored.
    check("engine reads suppressed techniques",
          "suppressed" in engine_src and "suppress" in engine_src.lower())
    check("engine gates effort advice on effort support",
          "supportsEffort" in engine_src)
    check("engine explains a withheld self-check to the user",
          "self-verifies" in engine_src)

if MODELS_SWIFT.exists():
    models_src = MODELS_SWIFT.read_text()
    # Every JSON key the Swift decoder declares as non-optional must exist
    # in every model entry. Catch the classic "added a field to Swift but
    # not the JSON" launch crash.
    declared = set(re.findall(r'case \w+ = "([a-z_]+)"', models_src))
    # Only assert on keys we know are model-level.
    model_level = declared & {
        "price_in_per_mtok", "price_out_per_mtok", "price_note",
        "one_liner", "default_effort", "best_fit",
        "suppress_techniques", "extra_instructions",
    }
    for m_ in models:
        for k in model_level:
            if k in ("price_note", "default_effort", "suppress_techniques",
                     "extra_instructions"):
                continue  # optional in Swift
            check(f"model '{m_['id']}' has decoder-required '{k}'", k in m_)

# --------------------------------------------- semantic / factual guards

by_id = {m["id"]: m for m in models}

# Opus 5's headline behavioral difference: it self-verifies, so verification
# techniques must be suppressed. If someone "helpfully" re-adds self_check
# to Opus 5, that regresses real prompt quality — fail loudly.
o5 = by_id.get("claude-opus-5", {})
check("Opus 5 suppresses self_check (it self-verifies)",
      "self_check" in o5.get("suppress_techniques", []))
check("Opus 5 thinking is on by default",
      o5.get("api_facts", {}).get("thinking_when_omitted") == "on_by_default")
check("Opus 5 records the disable-thinking effort ceiling",
      o5.get("api_facts", {}).get("disable_thinking_effort_ceiling") == "high")
check("Opus 5 priced at 5/25", o5.get("price_in_per_mtok") == 5.0
      and o5.get("price_out_per_mtok") == 25.0)

# Fable 5 cannot have thinking disabled at all.
f5 = by_id.get("claude-fable-5", {})
check("Fable 5 disallows explicit thinking disable",
      f5.get("api_facts", {}).get("explicit_disable_allowed") is False)

# Haiku has no effort ladder — suggesting one is an API error.
h = by_id.get("claude-haiku-4-5", {})
check("Haiku 4.5 has an empty effort ladder",
      h.get("api_facts", {}).get("effort_levels") == [])
check("Haiku 4.5 has no default_effort", h.get("default_effort") is None)

# No frontier model may claim to accept sampling params or prefill.
for mid in ("claude-opus-5", "claude-sonnet-5", "claude-fable-5", "claude-opus-4-8"):
    if mid in by_id:
        rejects = by_id[mid].get("api_facts", {}).get("rejects", [])
        for banned in ("temperature", "budget_tokens", "assistant_prefill"):
            check(f"{mid} rejects {banned}", banned in rejects)

# Cheapest-first ordering sanity: the recommender default must not be the
# most expensive model.
prices = {m["id"]: m["price_in_per_mtok"] for m in models}
check("recommender default isn't the most expensive model",
      prices.get(rec["default"], 0) < max(prices.values()))

# ------------------------------------------- source-hygiene / polish guards

VIEWS = ROOT / "ios/PromptCoach/PromptCoach/Views"
ALL_SWIFT = list((ROOT / "ios/PromptCoach/PromptCoach").rglob("*.swift"))

# Dynamic Type: a fixed .system(size:) font ignores the user's text-size
# setting. Accessibility review flags this, so keep the codebase free of it.
offenders = []
for p in ALL_SWIFT:
    for i, line in enumerate(p.read_text().splitlines(), 1):
        if ".system(size:" in line and not line.strip().startswith("///"):
            offenders.append(f"{p.name}:{i}")
check("no fixed-size fonts (Dynamic Type safe)", not offenders, str(offenders[:5]))

# No debug prints or leftover markers in shipping code.
for marker in ("print(", "TODO", "FIXME", "HACK"):
    hits = [f"{p.name}" for p in ALL_SWIFT if marker in p.read_text()]
    check(f"no '{marker}' in app sources", not hits, str(hits))

# Force-unwrap / crash-risk scan (allow the documented bundle fatalErrors).
risky = []
for p in ALL_SWIFT:
    src = p.read_text()
    if "try!" in src or re.search(r"\bas!\s", src):
        risky.append(p.name)
check("no try! / as! force casts", not risky, str(risky))

# Legal text must ship in-app: App Review opens Terms/Privacy, and a dead
# external link is a rejection.
settings = VIEWS / "SettingsView.swift"
if settings.exists():
    s = settings.read_text()
    check("Terms of Use ships in-app", "Terms of Use" in s)
    check("Privacy Policy ships in-app", "Privacy Policy" in s)
    check("legal copy is bundled, not remote-linked",
          "LegalText" in s and "http" not in s.split("enum LegalText")[-1][:400])

# Every screen the app can reach should exist.
for view in ("RambleView", "ResultView", "HistoryView", "LearnView",
             "SettingsView", "ModelReferenceView", "ModelDetailView",
             "TechniqueLibraryView", "LegalView"):
    found = any(f"struct {view}" in p.read_text() for p in ALL_SWIFT)
    check(f"view '{view}' is defined", found)

# The Sharpen feature declared in advanced_features must actually exist.
feature_ids = {f["id"] for f in af["features"]}
engine_all = (ROOT / "ios/PromptCoach/PromptCoach/Engine/CoachEngine.swift").read_text()
if "meta_prompt" in feature_ids:
    check("meta_prompt feature is implemented (sharpen)", "func sharpen(" in engine_all)
if "structured_mode" in feature_ids:
    check("structured_mode feature is implemented", "jsonSchema(" in engine_all)
if "report_card" in feature_ids:
    check("report_card feature is implemented", "buildReportCard(" in engine_all)

# Backward-compatible history: new CoachResult fields must be Optional, or
# upgrading users silently lose saved sessions.
check("new CoachResult flags are Optional for history compatibility",
      "var sharpened: Bool?" in engine_all,
      "non-optional new fields throw on older history JSON")

# ------------------------------------------------------------------ report

print(f"\n{'='*60}")
print(f"Prompt Coach pack contract tests — {len(passes)} passed, {len(failures)} failed")
print(f"pack_version: {pack['pack_version']}  models: {len(models)}  "
      f"techniques: {len(lib)}  playbooks: {len(playbooks)}")
print("=" * 60)
if failures:
    print("\nFAILURES:")
    for f in failures:
        print(f"  ✗ {f}")
    sys.exit(1)
print("\nAll contract tests passed ✓")
sys.exit(0)
