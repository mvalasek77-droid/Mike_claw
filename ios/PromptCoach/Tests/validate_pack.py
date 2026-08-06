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
ESTIMATOR = ROOT / "ios/PromptCoach/PromptCoach/Engine/TokenEstimator.swift"
STORE = ROOT / "ios/PromptCoach/PromptCoach/Store/LearningStore.swift"
RESULT_VIEW = ROOT / "ios/PromptCoach/PromptCoach/Views/ResultView.swift"
APP_TIER = ROOT / "ios/PromptCoach/PromptCoach/App/AppTier.swift"
APP_STATE = ROOT / "ios/PromptCoach/PromptCoach/Store/AppState.swift"
SETTINGS_VIEW = ROOT / "ios/PromptCoach/PromptCoach/Views/SettingsView.swift"
PROJECT_YML = ROOT / "ios/PromptCoach/project.yml"
INFO_LITE = ROOT / "ios/PromptCoach/PromptCoach/Resources/Info-Lite.plist"
HOSTED_TERMS = ROOT / "docs/prompt-coach-terms.html"
HOSTED_PRIVACY = ROOT / "docs/prompt-coach-privacy.html"
HOSTED_LITE_TERMS = ROOT / "docs/prompt-coach-lite-terms.html"
HOSTED_LITE_PRIVACY = ROOT / "docs/prompt-coach-lite-privacy.html"
HOSTED_SUPPORT = ROOT / "docs/prompt-coach-support.html"

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
# Optional in Swift (`TokenEstimation?` / `SelfLearning?`) so an older pack
# still decodes — but the shipping pack is expected to carry both, and the
# blocks below assert their shape.
OPTIONAL_TOP = ["token_estimation", "self_learning"]
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
             "TechniqueLibraryView", "LegalView", "LearningView"):
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

# ------------------------------------------- token efficiency (pack shape)

te = pack.get("token_estimation")
check("token_estimation block present", isinstance(te, dict))
fillers: list[str] = []
if isinstance(te, dict):
    for k in ("note", "chars_per_token", "multipliers", "multiplier_note",
              "filler_phrases", "filler_note"):
        check(f"token_estimation has '{k}'", k in te)
    check("chars_per_token is a positive number",
          isinstance(te.get("chars_per_token"), (int, float)) and te["chars_per_token"] > 0)

    mult = te.get("multipliers", {})
    missing_mult = model_ids - set(mult)
    check("every model has a tokenizer multiplier", not missing_mult, str(sorted(missing_mult)))
    stale_mult = set(mult) - model_ids
    check("no multipliers for models absent from the pack", not stale_mult, str(sorted(stale_mult)))
    check("all multipliers are positive numbers",
          all(isinstance(v, (int, float)) and v > 0 for v in mult.values()))
    # Haiku 4.5 predates the heavier tokenizer introduced with Opus 4.7; the
    # frontier models are on it. Getting this backwards under-prices Opus by
    # ~30%, which is exactly the kind of wrong number that erodes trust.
    check("Haiku 4.5 is the 1.0 tokenizer baseline", mult.get("claude-haiku-4-5") == 1.0)
    for mid in ("claude-sonnet-5", "claude-opus-5", "claude-fable-5", "claude-opus-4-8"):
        if mid in model_ids:
            check(f"{mid} uses the heavier tokenizer multiplier", mult.get(mid, 0) > 1.0)

    fillers = te.get("filler_phrases", [])
    check("filler_phrases non-empty", isinstance(fillers, list) and len(fillers) > 0)
    check("filler_phrases are lowercase (the matcher is case-insensitive)",
          all(isinstance(f, str) and f == f.lower() for f in fillers))
    check("filler phrases are unique", len(set(fillers)) == len(fillers))
    # A very short phrase is almost always a real word in disguise.
    stubby = [f for f in fillers if len(f) < 5]
    check("no filler phrase short enough to be a real word", not stubby, str(stubby))

# ---------------------------------- token efficiency (behaviour of the rule)
# A Python mirror of TokenEstimator.stripFiller. It can't prove the Swift is
# right, but it does prove the *rule* is safe for the phrase list the app
# actually ships — which is where a bad edit would land.


def strip_filler(text: str, phrases: list[str]) -> tuple[str, list[str]]:
    segments = text.split("```")
    ordered = sorted(phrases, key=len, reverse=True)
    removed: list[str] = []
    out: list[str] = []
    for i, seg in enumerate(segments):
        if i % 2 == 1:            # inside a fence — never touched
            out.append(seg)
            continue
        working, rounds, changed = seg, 0, True
        while changed and rounds < 4:
            changed, rounds = False, rounds + 1
            for phrase in ordered:
                pat = r"(?i)(\A|[.!?;,\n][ \t]*)" + re.escape(phrase) + r"\b,?[ \t]*"
                if re.search(pat, working):
                    working = re.sub(pat, r"\1", working)
                    changed = True
                    if phrase not in removed:
                        removed.append(phrase)
        out.append(working)
    return "```".join(out).strip(), removed


if fillers:
    # Meaning-bearing text that a careless whole-word trim would destroy.
    MUST_SURVIVE = [
        "what kind of file should this write to?",
        "do you know the answer to this",
        "only change just the header, nothing else",
        "compute the balance at the end of the day for each account",
        "sort of like a modal but inline",
        "the basically-correct answer is fine",
    ]
    for sentence in MUST_SURVIVE:
        out, _ = strip_filler(sentence, fillers)
        check(f"filler trim preserves: {sentence[:34]!r}", out == sentence, f"became {out!r}")

    MUST_TRIM = [
        ("ok so basically i need a function that parses dates",
         "i need a function that parses dates"),
        ("Could you please rewrite this paragraph", "rewrite this paragraph"),
        ("I was wondering if you could summarize the doc", "summarize the doc"),
        ("Basically, ship it. Thanks in advance", "ship it."),
    ]
    for raw, expected in MUST_TRIM:
        out, removed = strip_filler(raw, fillers)
        check(f"filler trim cleans: {raw[:34]!r}", out == expected,
              f"got {out!r}, wanted {expected!r}")

    fenced = "clean this up\n```\nbasically = 1\nok so = 2\n```\nthanks in advance"
    out, _ = strip_filler(fenced, fillers)
    check("filler trim never edits fenced code",
          "basically = 1" in out and "ok so = 2" in out, out)

    # Idempotence: coaching the same ramble twice must not keep eating text.
    once, _ = strip_filler("ok so basically fix the parser", fillers)
    twice, _ = strip_filler(once, fillers)
    check("filler trim is idempotent", once == twice, f"{once!r} -> {twice!r}")

# ------------------------------------------------ self-learning (pack shape)

sl = pack.get("self_learning")
check("self_learning block present", isinstance(sl, dict))
if isinstance(sl, dict):
    for k in ("note", "signals", "guardrails"):
        check(f"self_learning has '{k}'", k in sl)
    signals = sl.get("signals", [])
    check("self_learning declares signals", isinstance(signals, list) and len(signals) > 0)
    signal_ids = set()
    for s in signals:
        sid = s.get("id", "?")
        for k in ("id", "learns", "adjusts", "threshold"):
            check(f"signal '{sid}' has '{k}'", k in s)
        # A zero or negative threshold would fire a signal on no evidence.
        check(f"signal '{sid}' threshold is a positive int",
              isinstance(s.get("threshold"), int) and s.get("threshold", 0) >= 1)
        signal_ids.add(sid)
    check("signal ids unique", len(signal_ids) == len(signals))
    # LearningStore keys its logic off these exact ids; a rename in the pack
    # would silently stop the matching signal from ever firing.
    for required in ("model_override", "sharpen_rate", "acceptance",
                     "score_trend", "technique_mute"):
        check(f"self_learning declares the '{required}' signal", required in signal_ids)

    guardrails = sl.get("guardrails", [])
    check("self_learning states at least four guardrails", len(guardrails) >= 4)
    joined = " ".join(guardrails).lower()
    check("a guardrail forbids overriding per-model suppression", "suppression" in joined)
    check("a guardrail keeps learning local, inspectable and resettable",
          "local" in joined and "resett" in joined)
    check("a guardrail keeps learning to defaults only", "default" in joined)
    # The honesty constraint: this must never be described as a trained model.
    note = sl.get("note", "").lower()
    check("self_learning is described as on-device heuristics, not a trained model",
          "not a trained model" in note and "local" in note)

# ------------------------------------- new pack blocks reach the Swift side

if MODELS_SWIFT.exists():
    models_src = MODELS_SWIFT.read_text()
    check("decoder knows the token_estimation block",
          'case tokenEstimation = "token_estimation"' in models_src)
    check("decoder knows the self_learning block",
          'case selfLearning = "self_learning"' in models_src)
    # Optional, or an older/refreshed pack without these blocks crashes on
    # launch — the same class of bug as the history `sharpened` field.
    check("token_estimation is Optional in Swift",
          "let tokenEstimation: TokenEstimation?" in models_src)
    check("self_learning is Optional in Swift",
          "let selfLearning: SelfLearning?" in models_src)
    check("an unknown learning signal can never fire (unreachable threshold)",
          "Int.max" in models_src)
    if isinstance(te, dict):
        for k in te:
            check(f"decoder declares token_estimation key '{k}'",
                  f'"{k}"' in models_src or f"case {k}" in models_src)
    if isinstance(sl, dict):
        check("LearningSignal is defined", "struct LearningSignal" in models_src)
        for k in ("learns", "adjusts", "threshold"):
            check(f"decoder declares learning-signal key '{k}'", k in models_src)

# ------------------------------------------- estimator & learning behaviour

if ESTIMATOR.exists():
    est_src = ESTIMATOR.read_text()
    check("filler trim only fires at a clause start",
          r"\\A|[.!?;,\\n]" in est_src,
          "the clause-leading anchor is what keeps 'what kind of file' intact")
    check("filler trim skips fenced code", 'components(separatedBy: "```")' in est_src)
    check("filler trim loop is bounded (always terminates)", "rounds < 4" in est_src)
    check("token estimates carry a per-model tokenizer multiplier",
          "func multiplier(" in est_src)
    check("unknown model ids fall back to the 1.0 baseline rather than guessing",
          "return 1.0" in est_src)

if STORE.exists():
    store_src = STORE.read_text()
    check("learning never points at a model the pack dropped",
          "pack.model(id: top.key) != nil" in store_src)
    check("mutes are filtered to techniques the pack still defines",
          "pack.technique(id: $0) != nil" in store_src)
    check("learning thresholds come from the pack, not hardcoded in Swift",
          'spec.threshold("model_override")' in store_src
          and 'spec.threshold("sharpen_rate")' in store_src
          and 'spec.threshold("acceptance")' in store_src
          and 'spec.threshold("score_trend")' in store_src)
    check("no learning threshold is hardcoded in the store",
          not re.search(r">=\s*[2-9]\b", store_src),
          "thresholds must be read from the pack")
    # Same lesson as the history bug: a new counter must not wipe the old file.
    check("learning record decodes leniently (no data loss on upgrade)",
          store_src.count("decodeIfPresent") >= 6)
    check("learning is resettable in one call", "func reset()" in store_src)
    check("reset keeps explicit user choices (enabled + mutes)",
          "record.muted = muted" in store_src and "record.enabled = enabled" in store_src)
    check("the score trend window is bounded", "maxScores" in store_src)
    check("re-picking the recommended model is not counted as a preference",
          "guard modelID != recommendedID else { return }" in store_src)

if ENGINE.exists():
    check("engine consults the learned model preference",
          "learning.preferredModelByTask" in engine_src)
    check("engine consults the learned sharpen preference",
          "learning.autoSharpenTasks" in engine_src)
    check("engine honours muted techniques", "learning.mutedTechniques" in engine_src)
    # The guardrail that matters most: muting subtracts, so nothing learned
    # can re-enable a technique a model suppresses (e.g. Opus 5 self-check).
    check("muting can never re-enable a per-model suppression",
          "!suppressed.contains(id), !muted(id)" in engine_src)
    check("an explicit model override still beats a learned default",
          "overrideModelID ?? recommended" in engine_src)
    check("engine builds a token report", "func buildTokenReport(" in engine_src)
    check("the token report prices against the priciest model",
          "costOnPriciestUSD" in engine_src)
    check("the sharpened prompt is re-priced rather than left stale",
          engine_src.count("buildTokenReport(") >= 3)
    check("the filler trim runs before anything is added",
          "cleanCore(ramble)" in engine_src)

if RESULT_VIEW.exists():
    result_src = RESULT_VIEW.read_text()
    check("the token card labels its numbers as approximate",
          "approx" in result_src.lower() and "not an exact count" in result_src)
    check("the token card admits when structure made the prompt longer",
          "promptIsLonger" in result_src)
    check("copying the prompt feeds the acceptance signal",
          "noteAccepted" in result_src)

# ------------------------------------------------- the XCTest suite keeps up
# These can't run here (no Swift toolchain), but a feature shipping with no
# XCTest coverage at all is something this file *can* catch on any machine.

XCTESTS = ROOT / "ios/PromptCoach/Tests/PromptCoachTests/CoachEngineTests.swift"
if XCTESTS.exists():
    xc_src = XCTESTS.read_text()
    xc_names = re.findall(r"func (test\w+)", xc_src)
    check("XCTest names are unique (a duplicate silently replaces the first)",
          len(set(xc_names)) == len(xc_names))
    for area, needle in (
        ("filler trim safety", "stripFiller"),
        ("token report", "tokenReport"),
        ("per-model tokenizer multiplier", "multiplier(for:"),
        ("learned model preference", "preferredModelByTask"),
        ("auto-sharpen", "autoSharpenTasks"),
        ("technique muting", "mutedTechniques"),
        ("lenient learning-record decode", "LearningStore.Record"),
    ):
        check(f"XCTest covers {area}", needle in xc_src)
    # The two guardrails that would be worst to regress unnoticed.
    check("XCTest asserts an explicit override beats a learned default",
          "overrideModelID:" in xc_src and "adaptive_defaults" in xc_src)
    check("XCTest asserts muting can't re-enable a model suppression",
          "testMutingCanNeverReEnableAModelSuppression" in xc_src)

# ------------------------------------------------- free tier (Prompt Coach Lite)
# Two App Store listings, one codebase, no IAP: PromptCoachLite is the same
# sources compiled with a LITE flag. These checks can't compile Swift, so they
# verify the gate exists at the choke points that matter and that the two
# tiers stay in sync with the pack.

if APP_TIER.exists():
    tier_src = APP_TIER.read_text()
    check("AppTier declares a compile-time isLite flag", "static let isLite" in tier_src)
    check("AppTier is driven by the #if LITE build condition",
          "#if LITE" in tier_src, "must be compile-time, never a runtime toggle")
    m = re.search(r'liteModelIDs:\s*Set<String>\s*=\s*\[(.*?)\]', tier_src)
    check("AppTier declares liteModelIDs", m is not None)
    lite_ids = set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()
    check("Lite offers a small, fixed subset of models (2, not the full 5)",
          0 < len(lite_ids) < len(models), str(lite_ids))
    check("every Lite model id is a real model in the pack",
          lite_ids <= model_ids, str(lite_ids - model_ids))
    fb = re.search(r'liteFallbackModelID\s*=\s*"([^"]+)"', tier_src)
    check("AppTier declares a liteFallbackModelID", fb is not None)
    if fb:
        check("the Lite fallback model is itself one of the unlocked models",
              fb.group(1) in lite_ids, fb.group(1))
    check("a placeholder App Store URL is flagged for replacement before submission",
          "paidAppStoreURL" in tier_src and "replace" in tier_src.lower())

if MODELS_SWIFT.exists() and APP_TIER.exists():
    check("ModelPack exposes availableModels so every screen reads the "
          "same gated list instead of the raw model array",
          "var availableModels" in models_src and "AppTier.isLite" in models_src)
    check("ModelPack exposes lockedModels for the upsell rows",
          "var lockedModels" in models_src)

if ENGINE.exists():
    check("the engine clamps model routing to the unlocked set on Lite",
          "AppTier.isLite" in engine_src and "liteModelIDs" in engine_src)
    check("Sharpen is gated off on Lite",
          "func sharpen(" in engine_src and "guard !AppTier.isLite" in engine_src)
    check("the token/cost report is gated off on Lite",
          "guard !AppTier.isLite, estimator.isAvailable" in engine_src)

if STORE.exists():
    check("adaptive controls are unsupported on Lite (single choke point: isSupported)",
          "!AppTier.isLite && spec != nil" in store_src)
    check("the engine-facing snapshot also honours isSupported, not just the UI flag",
          re.search(r'var snapshot:.*?\n\s*guard isSupported', store_src, re.S) is not None,
          "if snapshot only checks `spec`, Lite could still learn even with the "
          "Settings section hidden")

if APP_STATE.exists():
    app_state_src = APP_STATE.read_text()
    check("Lite history is capped, not just thinned for display",
          "AppTier.isLite" in app_state_src and "liteHistoryLimit" in app_state_src)

if RESULT_VIEW.exists():
    check("the model override chips only ever offer availableModels on Lite",
          "app.pack.availableModels" in result_src)
    check("the Sharpen button is hidden on Lite, not just disabled",
          "if !AppTier.isLite { sharpenButton }" in result_src)

if SETTINGS_VIEW.exists():
    settings_src = SETTINGS_VIEW.read_text()
    check("Settings shows an upsell card on Lite",
          "AppTier.isLite" in settings_src and "struct UpsellCard" in settings_src)
    check("the model reference library shows locked models rather than "
          "hiding them outright (an honest map, not a bait-and-switch)",
          "app.pack.lockedModels" in settings_src)
    check("Lite ships its own Terms and Privacy text (no purchase to describe)",
          "termsLite" in settings_src and "privacyLite" in settings_src)
    lite_legal_block = settings_src.split("// MARK: Lite")[-1].split("// MARK: Paid")[0] \
        if "// MARK: Lite" in settings_src and "// MARK: Paid" in settings_src else ""
    check("Lite legal text says the app itself is free",
          "entirely free" in lite_legal_block.lower())
    check("Lite legal text never claims a purchase granted the license "
          "(that's the paid app's license clause, not this one)",
          "your one-time purchase grants" not in lite_legal_block.lower(),
          "found the paid app's purchase-grants-license clause inside the Lite block")

if PROJECT_YML.exists():
    yml = PROJECT_YML.read_text()
    check("project.yml defines a PromptCoachLite target", "PromptCoachLite:" in yml)
    check("PromptCoachLite shares PromptCoach's sources (one codebase, not a fork)",
          yml.count("path: PromptCoach\n") >= 2 or yml.count("path: PromptCoach") >= 2)
    check("PromptCoachLite has its own bundle id, distinct from the paid app",
          "com.codegenie.promptcoach.lite" in yml)
    check("PromptCoachLite compiles with the LITE flag",
          re.search(r'PromptCoachLite:.*?LITE', yml, re.S) is not None)
    check("PromptCoachLite has its own Info.plist (distinct display name)",
          "Info-Lite.plist" in yml)
    check("PromptCoachLite uses a dedicated App Store icon, not the paid icon",
          re.search(r'PromptCoachLite:.*?ASSETCATALOG_COMPILER_APPICON_NAME: AppIconLite',
                    yml, re.S) is not None)

check("a Lite Info.plist exists with a distinct display name", INFO_LITE.exists())
if INFO_LITE.exists():
    info_lite = INFO_LITE.read_text()
    check("Info-Lite.plist advertises the Lite name, not the paid app's name",
          "Prompt Coach Lite" in info_lite)

PAID_ICON = ROOT / "ios/PromptCoach/PromptCoach/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
LITE_ICON = ROOT / "ios/PromptCoach/PromptCoach/Resources/Assets.xcassets/AppIconLite.appiconset/icon-1024.png"
check("the paid target has a 1024px App Store icon", PAID_ICON.exists())
check("the Lite target has its own 1024px App Store icon", LITE_ICON.exists())
if PAID_ICON.exists() and LITE_ICON.exists():
    check("paid and Lite App Store icons are distinct files", PAID_ICON.read_bytes() != LITE_ICON.read_bytes())

# ------------------------------------- hosted legal/support pages (ASC links)
# App Review actually opens these — App Store Connect requires a live Privacy
# Policy URL, and a description that doesn't match what's found there is a
# real rejection risk (Guideline 2.3.1). The pages must describe only what
# v1.0 ships, not the roadmap.

for path, label in ((HOSTED_TERMS, "hosted Terms"), (HOSTED_PRIVACY, "hosted Privacy"),
                    (HOSTED_LITE_TERMS, "hosted Lite Terms"),
                    (HOSTED_LITE_PRIVACY, "hosted Lite Privacy"),
                    (HOSTED_SUPPORT, "hosted Support")):
    check(f"{label} page exists", path.exists())

if HOSTED_TERMS.exists() and HOSTED_PRIVACY.exists():
    hosted_legal = HOSTED_TERMS.read_text() + HOSTED_PRIVACY.read_text()
    check("hosted paid-app legal pages don't describe the unshipped Test It "
          "feature (v1.1 roadmap, not in this build)",
          "Test It" not in hosted_legal)
    check("hosted paid-app legal pages don't mention an Anthropic API key "
          "(no such field exists in v1.0)",
          "API key" not in hosted_legal)

# The non-affiliation disclaimer has to exist in all four places (hosted +
# in-app, both tiers) or App Review sees it in the app but not on the
# hosted page it actually opens, or vice versa.
disclaimer = "not affiliated with, endorsed by, or sponsored by anthropic"
if HOSTED_TERMS.exists():
    check("hosted paid Terms carries the Anthropic non-affiliation disclaimer",
          disclaimer in HOSTED_TERMS.read_text().lower())
if HOSTED_LITE_TERMS.exists():
    check("hosted Lite Terms carries the Anthropic non-affiliation disclaimer",
          disclaimer in HOSTED_LITE_TERMS.read_text().lower())
if SETTINGS_VIEW.exists():
    # Swift multi-line string literals use trailing `\` + newline for line
    # continuation — join those the way the compiler would before searching,
    # or a disclaimer that happens to wrap a line looks "missing".
    joined = re.sub(r'\\\n\s*', '', settings_src.lower())
    check("in-app Terms (both tiers) carry the Anthropic non-affiliation "
          "disclaimer at least twice (paid + Lite)",
          joined.count(disclaimer) >= 2)

if HOSTED_LITE_TERMS.exists() and HOSTED_LITE_PRIVACY.exists():
    hosted_lite_legal = HOSTED_LITE_TERMS.read_text() + HOSTED_LITE_PRIVACY.read_text()
    check("hosted Lite legal pages say the app is free, not purchased",
          "free" in hosted_lite_legal.lower())
    check("hosted Lite legal pages link back to the paid app's own pages "
          "rather than restating its terms",
          "prompt-coach-privacy.html" in hosted_lite_legal
          or "prompt-coach-terms.html" in hosted_lite_legal)

if HOSTED_SUPPORT.exists():
    hosted_support = HOSTED_SUPPORT.read_text()
    check("support page tells users how Apple refunds work "
          "(we can't issue them directly)",
          "reportaproblem.apple.com" in hosted_support)
    check("support page states the app isn't from Anthropic "
          "(trademark/endorsement clarity)",
          "not" in hosted_support.lower() and "anthropic" in hosted_support.lower())
    check("support page covers both listings, not just one",
          "Prompt Coach Lite" in hosted_support and "Prompt Coach" in hosted_support)

if PROJECT_YML.exists():
    check("no hosted page claims a feature this app doesn't have: "
          "grep the whole docs/ prompt-coach-*.html set for 'Test It' once more",
          not any("Test It" in p.read_text()
                  for p in (ROOT / "docs").glob("prompt-coach*.html")))

DEPLOY_WORKFLOW = ROOT / ".github/workflows/deploy-pages.yml"
if DEPLOY_WORKFLOW.exists():
    wf = DEPLOY_WORKFLOW.read_text()
    check("the Pages deploy workflow actually triggers on this branch "
          "(it shipped scoped to a different branch — dead pages otherwise)",
          "claude/prompt-coach-github-search-zxwm0e" in wf)

# The privacy claim is load-bearing for the Privacy Policy and for App Review.
networked = [p.name for p in ALL_SWIFT if "URLSession" in p.read_text()]
check("no network calls anywhere in the app", not networked, str(networked))

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
