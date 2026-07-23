# Prompting Techniques Library — the coach's knowledge base

This is what makes the app "how to prompt Claude correctly," not just a model
picker. Every technique below is the coach's toolkit: given a ramble, a task
type, and a target model, the app applies the relevant techniques, rewrites the
prompt, and **teaches the user which technique it used and why**.

**Source & honesty note.** These are Anthropic's official, current
prompt-engineering techniques — pulled from
`platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices`
(verified July 2026), cross-checked against the model migration guidance. I
deliberately weighted the official docs over social/X "prompt hacks" because
most of those are stale for the Claude 5 / Opus 4.8 / Fable 5 era — they still
push prefill, `temperature`, and fixed thinking budgets that these models now
reject. The "Retired techniques" section at the end lists what to stop doing.

The machine-readable version (for the app to load) is the `techniques` block in
`docs/model-pack.json`.

---

## Foundational principles (apply to almost every ramble)

### 1. Be clear and direct
Treat Claude like a brilliant new colleague with zero context on your norms.
Spell out exactly what you want, the output format, and constraints. If you want
"above and beyond," ask for it — the model won't infer ambition from a vague
prompt. **Golden rule:** if a colleague with no context would be confused by the
prompt, so is Claude.
**Coach applies:** turn "make it good" into a concrete deliverable; add explicit
format/constraint lines; number steps when order matters.

### 2. Add context / motivation (say *why*)
Explaining the reason behind an instruction lets Claude generalize correctly.
"Never use ellipses" is weak; "this is read aloud by text-to-speech, which can't
pronounce ellipses" is strong.
**Coach applies:** prepend the intent — "I'm doing X for Y so they can Z" — which
also happens to be the single biggest lever on Fable 5.

### 3. Use examples (multishot)
A few well-chosen examples are the most reliable way to lock output format, tone,
and structure. Use **3–5** examples that are relevant (mirror the real case),
diverse (cover edge cases, no accidental pattern), and structured (each in
`<example>` tags, all inside `<examples>`).
**Coach applies:** when output shape matters, offer to add an example block;
especially high-value for Haiku 4.5, which follows examples well.

### 4. Structure with XML tags
XML tags let Claude tell instructions from context from input. Wrap each kind of
content in its own tag — `<instructions>`, `<context>`, `<input>` — with
consistent, descriptive names; nest when there's a hierarchy.
**Coach applies:** when a ramble mixes an ask with pasted data/code, split them
into tagged sections instead of one run-on blob.

### 5. Give Claude a role
One sentence of role in the system prompt measurably focuses tone and behavior
("You are a senior Python reviewer").
**Coach applies:** derive a role from the task and put it up front / suggest it
as a system prompt.

### 6. End with a success criterion
State how the result will be judged — "done means…". The highest-leverage single
addition across every model and task.
**Coach applies:** always appends an acceptance test drawn from the ramble.

---

## Output & formatting control

### 7. Say what TO do, not what NOT to do
"Write in flowing prose paragraphs" beats "don't use markdown." Positive framing
steers more reliably than prohibitions.
**Coach applies:** rewrites negative constraints as positive instructions.

### 8. Format indicators & prompt-style matching
Ask for output inside a named XML tag (`<summary>…`), and match your prompt's
own style to the output you want — markdown-heavy prompts beget markdown-heavy
answers, so strip markdown from the prompt if you want prose.
**Coach applies:** picks a format indicator when the user needs a machine-readable
or specific shape.

### 9. Control verbosity deliberately
Current models are concise by default and may skip post-tool summaries. If you
want more (or less), say so — and prefer positive examples of the length you want
over "be brief."
**Coach applies:** adds a verbosity line matched to the task and model (e.g.
silence-default for Opus 4.8 coding agents).

### 10. Plain text vs LaTeX
Current models default to LaTeX for math. If you need plain text, say so
explicitly ("use `/` for division, `^` for exponents, no `$` or `\frac`").
**Coach applies:** adds the plain-text instruction when the target isn't a
LaTeX-rendering surface.

### 11. Structured outputs instead of prefill
To force JSON/schema/classification output, use the Structured Outputs feature or
a clear "conform to this schema" instruction — **not** a prefilled assistant turn
(removed; see Retired).
**Coach applies:** recommends structured outputs for machine-readable results.

---

## Reasoning & thinking

### 12. Let the model think (adaptive)
On current models thinking is adaptive — depth is driven by `effort` + query
complexity, not a token budget. General instructions ("think through this
carefully") beat hand-written step-by-step plans; the model's own reasoning
usually exceeds a prescribed one.
**Coach applies:** for hard tasks, adds a "reason it through before answering"
nudge rather than enumerating steps; recommends an effort level.

### 13. Manual chain-of-thought (fallback when thinking is off)
When thinking is disabled (or on Haiku 4.5), ask for step-by-step reasoning and
separate it from the answer with `<thinking>` and `<answer>` tags.
**Coach applies:** on Haiku or thinking-off prompts, structures reasoning vs
final answer.

### 14. Ask Claude to self-check
Append "before you finish, verify your answer against [criteria]." Catches errors
reliably, especially coding and math.
**Coach applies:** adds a self-check line for correctness-sensitive tasks.

### 15. Commit to an approach (anti-overthinking)
For higher-effort models prone to over-exploring: "choose an approach and commit;
don't revisit unless new information contradicts it."
**Coach applies:** adds this when the ramble is open-ended and the target is a
high-effort model.

---

## Tool use & agentic (for prompts that drive tools/agents)

### 16. Be explicit about taking action
"Suggest changes" gets suggestions; "make these changes" gets edits. State
whether you want action or just analysis.
**Coach applies:** disambiguates action-vs-advice from the ramble's intent.

### 17. Trigger conditions in tool descriptions
Tell the model *when* to use a tool ("call this when the answer depends on current
prices"), in the tool's own description — biggest lever for Opus 4.8's
conservative tool triggering.
**Coach applies:** suggests when/how-to-use lines for any tools the task mentions.

### 18. Parallel tool calls
Independent calls should run in parallel; this is steerable to ~100% with an
explicit instruction.
**Coach applies:** adds the parallel-calls instruction for multi-read/multi-search
agent prompts.

### 19. Autonomy & safety balance
Grant local reversible actions freely; require confirmation before destructive or
hard-to-reverse ones (deletes, force-push, external posts).
**Coach applies:** adds an autonomy line — small decisions proceed, risky ones
ask — tuned per model (Opus 4.8 asks too much by default; Fable 5 needs explicit
"report and stop" boundaries).

### 20. Long-horizon state tracking
For multi-window/agentic work: incremental progress, tests in a structured file
(`tests.json`), git for checkpoints, progress notes; don't stop early on token
budget if the harness compacts.
**Coach applies:** for big autonomous asks, structures the prompt around
incremental progress + a state file.

### 21. Ground answers / anti-hallucination
"Never speculate about code you haven't opened; read the file before answering."
Current models hallucinate less, and this makes it near-zero.
**Coach applies:** adds an investigate-before-answering clause for codebase Q&A.

### 22. Self-correction chaining
The most useful multi-call pattern: draft → review against criteria → refine.
**Coach applies:** for high-stakes output, suggests splitting into a draft +
review pass.

---

## Capability-specific

### 23. Long-context layout
Put long documents/data at the **top**, the question at the **end** (up to +30%
quality on multi-doc tasks). Wrap each doc in `<document>` with `<source>` +
`<document_content>`. Ask the model to quote relevant passages first.
**Coach applies:** reorders pasted long content above the ask and tags it.

### 24. Anti-"AI slop" frontend
For UI/design prompts: demand distinctive typography, a committed color theme,
purposeful motion, and atmospheric backgrounds; explicitly ban generic fonts
(Inter/Roboto/Arial) and clichéd purple-gradient-on-white.
**Coach applies:** injects the anti-slop design brief for frontend/design rambles.

### 25. Vision crop
For image tasks, giving the model a crop/zoom tool measurably improves accuracy.
**Coach applies:** notes this for image-analysis prompts.

---

## Retired techniques (stop doing these — the "stale X hacks")

The coach actively strips these if it sees them in a ramble, and never adds them:

- **Prefilling the assistant turn** to force format or skip preamble → **400
  error** on Sonnet 5 / Opus 4.8 / Fable 5. Use structured outputs or a direct
  "respond directly, no preamble" instruction.
- **Setting `temperature` / `top_p` / `top_k`** for the frontier three → rejected.
  Steer with words; use propose-then-pick for variety.
- **Fixed thinking budgets (`budget_tokens`)** → rejected on Opus 4.7+ and Fable
  5. Control depth with `effort`.
- **Aggressive "CRITICAL: YOU MUST"** tool language → current models are highly
  instruction-following and now *overtrigger*. Use normal "Use this when…" phrasing.
- **"If in doubt, use [tool]" / blanket "always"** defaults → cause overtriggering;
  make them conditional.
- **Prescriptive step-by-step reasoning plans** on frontier models → often worse
  than "think it through"; the model's own plan usually beats a hand-written one.

---

## How the coach uses this library

1. Classify the ramble's task type (email, code, SQL, research, design, agentic…).
2. Pick the target model (or take the recommender's suggestion).
3. Select the techniques whose trigger matches the task + model, apply them in the
   rewrite, and drop any retired patterns found in the ramble.
4. In "What I changed," name each technique used ("Added a role", "Moved your data
   to the top and tagged it", "Added a success criterion") so the user learns the
   method, not just the result.

That last step is the product: every coached prompt is also a lesson in how to
prompt Claude correctly.
