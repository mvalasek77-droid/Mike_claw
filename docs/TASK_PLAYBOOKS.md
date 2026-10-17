# Task Playbooks — the coach's rewrite recipes

For each task type the coach detects, this is the recipe: which model to
recommend, which techniques (from `PROMPTING_TECHNIQUES.md`) to apply and in what
order, and the output shape. This is what makes the rewrite deterministic instead
of vibes — the build wires these, the machine-readable form is `task_playbooks`
in `docs/model-pack.json`.

Technique IDs referenced below are defined in `PROMPTING_TECHNIQUES.md` /
`model-pack.json → techniques.library`.

---

## email / message reply
- **Recommend:** Haiku 4.5 (Sonnet 5 if the situation is delicate/nuanced).
- **Techniques, in order:** `add_context` (relationship + situation) → `clear_direct` (tone, length cap) → `examples` (only if voice must match) → `success_criterion`.
- **Output:** the message text, tight; no meta-commentary.
- **Key move:** capture the *stance* (apologetic? firm? offering credit not cash?) — that's what a ramble usually buries.

## code generation / editing
- **Recommend:** Sonnet 5 (default); Opus 4.8 for large or multi-file work.
- **Techniques:** `clear_direct` (exact behavior + language/framework) → `xml_structure` (paste existing code in a tag) → `explicit_action` (make the change vs suggest) → `adaptive_thinking` (hard logic) → `self_check` (verify against tests) → `anti_hallucination` (read files before claiming) → `success_criterion` (tests pass / behavior).
- **Output:** the code, plus a one-line what-changed.
- **Key move:** state the acceptance test as real behavior, not "make it work."

## SQL / data query
- **Recommend:** Sonnet 5 (Haiku 4.5 if trivial).
- **Techniques:** `xml_structure` (schema block) → `clear_direct` (exact result set) → `examples` (a couple of sample rows) → `success_criterion` (columns, filters, ordering) → `self_check`.
- **Output:** the query, dialect-correct.
- **Key move:** pin the dialect (Postgres/MySQL/…) and the join keys — the usual source of wrong answers.

## debugging
- **Recommend:** Opus 4.8 or Sonnet 5.
- **Techniques:** `xml_structure` (error + code + repro steps in separate tags) → `anti_hallucination` (read the file first) → `adaptive_thinking` → `commit_approach` (don't thrash) → `self_check`.
- **Output:** root cause + the fix.
- **Key move:** separate the symptom, the code, and what's already been tried.

## research / synthesis
- **Recommend:** Opus 4.8 (Fable 5 for genuinely hard/novel questions).
- **Techniques:** `success_criterion` (what a good answer contains) → `add_context` (why you need it) → `tool_triggers` (search-first when currency matters) → `state_tracking` (hypothesis notes) → `self_correction_chain`.
- **Output:** the synthesis with sources.
- **Key move:** define "done" up front so it doesn't wander.

## long-form writing
- **Recommend:** Fable 5 or Opus 4.8.
- **Techniques:** `role` → `add_context` (audience + purpose) → `examples` (voice) → `do_not_dont` (prose vs bullets) → `verbosity` → `success_criterion`.
- **Output:** the piece.
- **Key move:** name the reader and the outcome; for variety use propose-then-pick, never temperature.

## summarize / extract
- **Recommend:** Haiku 4.5 or Sonnet 5.
- **Techniques:** `long_context` (source doc at the top, ask at the end) → `clear_direct` (what to pull) → `structured_outputs`/`format_indicator` → `success_criterion`.
- **Output:** the summary or the structured extraction.
- **Key move:** put the document first, the instruction last (+30% on multi-doc).

## classification
- **Recommend:** Haiku 4.5.
- **Techniques:** `examples` (multishot labelled cases) → `structured_outputs` (enum of valid labels) → `clear_direct` → `success_criterion`.
- **Output:** the label (machine-readable).
- **Key move:** give the label set as an enum and 3–5 examples; don't over-explain.

## design / frontend
- **Recommend:** Opus 4.8 or Sonnet 5.
- **Techniques:** `anti_slop_frontend` → `add_context` (brand, audience, mood) → `format_indicator` (stack/constraints) → `explicit_action` → `success_criterion`.
- **Output:** the UI/code, or 3–4 proposed directions to pick from.
- **Key move:** commit to a distinct aesthetic; propose-then-pick for range.

## agentic / automation
- **Recommend:** Opus 4.8 (Fable 5 for the hardest long-horizon runs).
- **Techniques:** `clear_direct` (full spec up front, one turn) → `tool_triggers` → `parallel_tools` → `autonomy_safety` → `state_tracking` → `anti_hallucination` → `self_check`.
- **Output:** the agent/system prompt.
- **Key move:** front-load the entire goal + constraints + definition of done; add the autonomy line so it neither stalls nor over-reaches.

---

## Level-up features (the "next level" layer)

Optional power features on top of the core ramble → clean-prompt loop. Encoded as
`advanced_features` in `docs/model-pack.json`.

### Sharpen it further (meta-prompting)
A second pass that critiques and improves the already-coached prompt — the
`self_correction_chain` technique turned on the prompt itself: draft → review
against the technique checklist + task playbook → refine. Runs on device from the
rules, or (with the optional Test It key) as a model-graded pass. Surfaced as a
"Sharpen" button on any coached prompt.

### Structured-output mode
For code / SQL / classify / extract tasks, the app emits the coached prompt **plus
a ready JSON Schema** generated from the acceptance criteria, with a "conform to
this schema" instruction (the `structured_outputs` technique) — never prefill. The
user gets reliably parseable results, not prose they have to scrape.

### Prompt-cache-aware layout
Orders the prompt so the stable, reusable part (role, standing instructions,
reference docs) comes first and the volatile ask comes last, and marks the
reusable prefix. Repeated runs on the same key then hit the prompt cache at ~10%
of input cost — a real saving for anyone running a prompt many times.

### Prompt report card
Scores the **original** ramble against the technique checklist so the user sees
exactly what was missing before the rewrite fixes it. Checklist: clear ask,
context/why, role, examples, XML structure for pasted data, explicit scope,
success criterion, and no retired patterns (prefill / temperature /
`budget_tokens` / CRITICAL-language). Returns a 0–100 score plus per-item
pass/fail; the coached prompt then shows each fix. This is the teaching flywheel —
users watch their raw prompts score higher over time.

---

## Refusal handling — getting *legitimate* requests through (not a jailbreak)

Some legitimate prompts get wrongly refused because the phrasing pattern-matches
to misuse: a security engineer asking about an exploit for an authorized pentest,
a clinician asking a dosage question, a novelist writing a violent scene, a
researcher studying extremist rhetoric. These are **false positives**, and the
fix is the opposite of a jailbreak — you add legitimacy, you don't hide it.

**What the coach does when a ramble looks refusal-prone:**
- **State the benign context and purpose.** "For an authorized penetration test
  of my own staging server…", "I'm a registered nurse charting…", "For a novel,
  a scene where…". Anthropic's guidance is explicit: clear context reduces bad
  refusals, and current models refuse more appropriately when intent is legible.
- **Be specific about scope and role.** Vague + edgy reads as risky; specific +
  contextualized reads as legitimate.
- **Give permission to express uncertainty / decline partially.** "If any part of
  this is something you can't help with, do the rest and say which part you
  skipped." Reduces all-or-nothing refusals and hallucination.
- **Handle a genuine refusal gracefully.** On Fable 5, bio/cyber requests can
  return `stop_reason: "refusal"`; the app surfaces that honestly and (if the
  optional Test It key is set) can fall back to Opus 4.8 — it does not try to
  defeat the classifier.

**What the coach will NOT do — and the app states this in its policy:**
- It will not craft prompts whose goal is to bypass safety systems or produce
  genuinely disallowed content (weapons, CSAM, real-world harm, malware for
  unauthorized targets, etc.). Adding fake "authorization" or role-play wrappers
  to get around a *correct* refusal is out of scope. Encoding that would violate
  Anthropic's usage policy, get the API key revoked, and get the app pulled from
  the App Store.

The line is simple: **help a real, legitimate request be understood as
legitimate — never help disguise a disallowed one.**
