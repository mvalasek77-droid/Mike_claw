# Claude Model Prompting Notes — source of truth for the coach

Expanded research notes on how each Claude model the app targets is best
prompted. These are the rewrite rules the coach applies; the machine-readable
version lives in `docs/model-pack.json`. Verified against Anthropic's current
model guidance, July 2026.

Three models, three completely different temperaments. The single biggest
mistake is prompting all three the same way — a prompt tuned for one is often
actively wrong for another.

---

## The one-line mental model

| Model | ID | Temperament | Prompt it like… |
|---|---|---|---|
| Haiku 4.5 | `claude-haiku-4-5` | Fast and literal, shallow | a quick assistant — one clear task, spell out the output |
| Sonnet 5 | `claude-sonnet-5` | Takes you literally | a precise contractor — spell out scope, it won't infer |
| Opus 4.8 | `claude-opus-4-8` | Deliberate autonomous worker | a senior engineer — hand over the whole spec up front |
| Fable 5 | `claude-fable-5` | Frontier reasoner, resents micromanagement | a domain expert — give the goal and the *why*, not the steps |

**Efficiency first: pick the cheapest model that clears the task's bar.** Most
rambles do not need Opus or Fable. The recommender below maps the ramble to a
model; when two clear the bar, take the cheaper one.

---

## Model recommender (efficiency lever)

The app suggests a model from the ramble's shape so users don't overpay. Default
is Sonnet 5; the user can always override.

| Ramble looks like… | Recommend | Why |
|---|---|---|
| Simple, single-step: classify, format, extract, short reply, quick lookup; or explicitly high-volume / latency-sensitive | **Haiku 4.5** | Cheapest and fastest; no deep reasoning needed |
| Literal, well-scoped, structured; most coding; medium complexity where predictability matters | **Sonnet 5** | Near-Opus quality at Sonnet cost — the sensible default |
| Long, multi-step, autonomous: refactors, overnight builds, deep research, end-to-end deliverables | **Opus 4.8** | State-of-the-art long-horizon autonomy |
| The hardest novel reasoning or frontier problems where lesser models plateau | **Fable 5** | Deepest reasoning; justifies top price only when it pays off |

Tie-breaker: when two models both clear the bar, pick the cheaper one. If Haiku
can't hold the reasoning, that's the signal to move up to Sonnet 5 — not to pile
more instructions onto Haiku.

## Claude Haiku 4.5 — the cheap, fast one

**Core trait: fast, literal, and shallow.** Lowest cost and latency in the
family, but not a reasoner. Use it for simple, well-defined, single-step work;
the moment a task needs planning or multi-step reasoning, move up to Sonnet 5.

**Rewrite rules the coach applies:**

1. **Keep it simple and concrete.** Spell out exactly what you want — Haiku
   won't infer intent or fill gaps the way the bigger models do.
2. **One clear task per prompt.** Don't ask it to plan multi-step work; decompose
   first or escalate to Sonnet 5.
3. **Nail the output shape.** Use an explicit format instruction or structured
   outputs; a short worked example helps a lot — Haiku follows examples well.
4. **No effort/adaptive-thinking advice.** Haiku 4.5 has no `effort` parameter
   (it errors) and uses the older `budget_tokens` thinking style, off by default.
   If a task seems to need reasoning, that's a signal to move up, not to bolt
   thinking onto Haiku.
5. **It accepts what the others reject** — sampling params and prefill work on
   Haiku 4.5 — but steering with words stays the portable habit.

**Best-fit jobs:** classify / format / extract / short reply, high-volume or
latency-sensitive pipelines where per-call cost dominates.

## Claude Sonnet 5 — the literal one

**Core trait: literal, explicit instruction-following.** It does exactly what
you asked and does not generalize an instruction from one item to the rest, nor
infer requests you didn't make. This is a feature — it makes Sonnet 5 the most
predictable of the three for structured extraction, high-volume pipelines, and
carefully tuned prompts — but it punishes vague prompts hard.

**Rewrite rules the coach applies:**

1. **Make scope explicit.** Any instruction that should apply broadly must say
   so. "Fix the bug" → "Fix the bug everywhere it appears, not just the first
   occurrence." "Format the section" → "Apply this formatting to every section."
   If the ramble implies a rule but states it once, the coach restates it as
   universal.
2. **Convert vague asks into concrete deliverables.** "Make it good" is useless
   here; the coach forces a definition of done ("Output a CSV with a numeric
   `price` column for every SKU").
3. **Control verbosity with positive examples, not prohibitions.** Sonnet 5
   calibrates response length to task complexity. To tighten it, the coach adds
   "Provide concise, focused responses; skip non-essential context and keep
   examples minimal" rather than "don't be verbose." Positive examples of the
   desired output beat negative instructions.
4. **No sampling settings.** Sonnet 5 rejects `temperature`/`top_p`/`top_k`. The
   coach never emits them and steers tone/variety with words. For creative
   variety (design, copy), it uses propose-then-pick: "Propose 3–4 distinct
   directions, then implement the one I choose" — the reliable substitute for a
   temperature knob.
5. **Effort awareness.** Defaults to `high`. The coach recommends `xhigh` for
   the hardest coding/agentic tasks. It flags that Sonnet 5 respects `low`/
   `medium` strictly and may under-think there — the fix is to raise effort, not
   to add "think harder" prose.
6. **Tool nudge when thinking is off.** Sonnet 5 is agentic by default and
   reaches for tools readily — but with thinking disabled it becomes tool-shy.
   If the prompt runs thinking-off and depends on a tool, the coach adds an
   explicit trigger ("When the answer depends on current information, call the
   search tool before answering").
7. **Drop stale progress scaffolding.** Its default in-progress updates are
   good; the coach removes "summarize every N tool calls" leftovers.

**Best-fit jobs:** literal, well-scoped, high-volume, structured tasks; drafting
and extraction where predictability matters; anything cost-sensitive that
doesn't need frontier reasoning.

---

## Claude Opus 4.8 — the deliberate autonomous worker

**Core trait: state-of-the-art long-horizon autonomy, but under-reaches for
capabilities and asks permission more than you'd expect.** It plans well and
finishes complex work without correction — if you set it up right up front.

**Rewrite rules the coach applies:**

1. **Front-load the entire spec in one turn.** The coach consolidates a scattered
   ramble into a single well-specified brief: goal, inputs, constraints, and
   definition of done — then recommends `high` or `xhigh` effort. Opus 4.8's
   coherence comes from planning against a clear goal it has from the start;
   dribbling requirements out over multiple turns hurts it.
2. **Say when capabilities should fire.** Opus 4.8 is conservative about search,
   subagents, file-based memory, and custom tools — it won't reach for something
   complex unless it's fairly sure it's needed. The coach adds explicit trigger
   lines: "Search before answering when the answer depends on current
   information"; "Delegate to subagents when the task fans out across independent
   items." It also recommends putting the trigger condition in each tool's own
   description ("Call this when the user asks about current prices") — prescriptive
   descriptions give measurable lift on this model.
3. **Grant autonomy on small decisions.** Opus 4.8 pauses on trivial choices and
   closes tasks with "Want me to also…?". The coach adds: "For minor choices
   (naming, defaults, equivalent approaches), pick a reasonable option and note
   it. For scope changes or destructive actions, still ask first." (In Claude
   Code testing this cut ask-rate ~12 points with no rise in over-reach.)
4. **Manage narration.** It narrates more than 4.7 by default. The coach removes
   forced-progress scaffolding, and adds a silence-default ("Default to silence
   between tool calls; write only when you find something, change direction, or
   hit a blocker") when the user wants a terse coding agent.
5. **Effort: start at `high`, don't reflexively use `xhigh`.** Higher effort up
   front often *reduces* total turn count and cost on agentic work; the coach
   suggests sweeping `medium`/`high`/`xhigh` rather than defaulting to the ceiling.
6. **Re-check warmth prompts.** Opus 4.8 writes warmer and less hedged than 4.7.
   Style prompts written to counter earlier terseness may now overcorrect — the
   coach flags them for review rather than blindly keeping them.
7. **Thinking-off leak guard.** With thinking disabled it can leak reasoning into
   the response; the coach adds "Respond only with your final answer" or keeps
   adaptive thinking on.

**Best-fit jobs:** long, autonomous, multi-step work — refactors, overnight
builds, deep research, end-to-end deliverables — where you can specify the whole
job up front.

---

## Claude Fable 5 — the frontier reasoner that resents micromanagement

**Core trait: deepest reasoning of the three, and over-prescription actively
degrades it.** Its biggest gains are on work *above* what prior models could do,
so it's wasted on routine tasks. Give it hard problems and room to think.

**Rewrite rules the coach applies:**

1. **Strip the step-by-step; keep goal + constraints + acceptance test.** Prompts
   and skills written for older models are often too prescriptive and *reduce*
   Fable's quality. The coach removes enumerated steps and lets Fable plan,
   keeping only the goal, hard constraints, and how success is judged.
2. **Give the reason, not just the request.** The coach prepends intent: "I'm
   building X for Y; they need Z — with that in mind, [request]." Fable connects
   the task to relevant context instead of guessing intent, which matters most
   on long agentic runs juggling disparate context.
3. **Invest in an explicit communication-style section.** Fable is extremely
   responsive to these. Un-steered at high effort it over-elaborates (heavily
   structured PR-style outputs, sections on rejected alternatives, comments
   narrating the next line). The coach adds a short "lead with the outcome; be
   selective about what you include rather than compressing into shorthand"
   addendum.
4. **Plan for minutes-long turns.** A single hard request can run 15+ minutes at
   high effort. The coach warns when a prompt implies a long autonomous run and
   suggests structuring for streaming / async check-ins rather than blocking.
5. **State boundaries explicitly.** Fable occasionally takes unrequested-but-
   adjacent actions (drafting an email straight to drafts, creating backup
   branches). The coach adds "When the user is asking a question or thinking out
   loud, report your assessment and stop — don't apply a fix until asked," plus
   any "don't do X" the task needs.
6. **Encourage delegation and memory.** Parallel subagents are dependable on
   Fable — the coach encourages using them (asynchronously, so the orchestrator
   isn't blocked) and giving Fable a memory file to record learnings for future
   sessions.
7. **Effort sweep, low is fine.** `low`/`medium` on Fable often beat the
   `xhigh`/`max` output of previous models. The coach defaults to `high` and
   reserves `xhigh`/`max` for the most capability-sensitive work; it flags that
   higher effort on routine work can cause unnecessary tidying/refactoring.
8. **Ground progress claims on long runs.** For long autonomous work the coach
   adds "Before reporting progress, audit each claim against a tool result from
   this session" — this nearly eliminates fabricated status reports.

**Best-fit jobs:** the hardest reasoning and long-horizon problems — novel
system design, first-shot implementations of well-specified systems, deep
analysis — where frontier capability justifies the higher price.

---

## API facts the coach must get exactly right (per model)

Prompt craft is above; these are the hard API facts. If the coach ever emits a
"recommended settings" line alongside the prompt, it must not contradict these,
and it must never suggest a parameter a model rejects. Verified July 2026.

| Fact | Haiku 4.5 | Sonnet 5 | Opus 4.8 | Fable 5 |
|---|---|---|---|---|
| Model ID | `claude-haiku-4-5` | `claude-sonnet-5` | `claude-opus-4-8` | `claude-fable-5` |
| Thinking when `thinking` omitted | **OFF** (older style) | **Adaptive ON** | **OFF** — set `{type:"adaptive"}` | **Always on** — omit the param |
| Explicit `{type:"disabled"}` | Allowed | Allowed | Allowed | **400 error** |
| `budget_tokens` | **Used** (min 1024, < max_tokens) | **400** | **400** | **400** |
| Sampling (`temperature`/`top_p`/`top_k`) | **Accepted** (one of temp/top_p) | Non-default → **400** | Non-default → **400** | **400** |
| Last-assistant-turn prefill | **Accepted** | **400** | **400** | **400** |
| Effort levels | **None** (errors) | low→max (default high) | low→max (default high) | low→max (default high) |
| Refusal (`stop_reason:"refusal"`) | Rare | Possible (cyber) | Rare | **Likely for bio/cyber** — handle + fallbacks |
| Context / max output | 200K / 64K | 1M / 128K | 1M / 128K | 1M / 128K |
| Data retention | Standard | Standard | Standard | **Requires 30-day; ZDR → 400** |
| Extras | Older API surface; keep prompts simple | ~30% heavier tokenizer than 4.6; Bedrock forced `tool_choice` needs thinking off | Mid-session `role:"system"` messages (4.8 only) | Raw chain-of-thought never returned; read summarized `thinking` |

**Depth is controlled by `effort`, not a token budget** on all three — there is
no fixed thinking-token budget anymore. Recommend adaptive thinking when
reasoning is wanted, and remember the default differs (Sonnet on, Opus off,
Fable always). To stream visible reasoning, set `thinking.display:"summarized"`
(the default `omitted` streams empty thinking blocks — looks like a pause).

## Cross-model rules (apply to all)

These are constants the coach enforces regardless of target:

1. **Don't suggest `temperature`/`top_p`/`top_k` or prefill tricks for the
   frontier three** (Sonnet 5, Opus 4.8, Fable 5) — they reject them; steer with
   words, and use propose-then-pick for variety. (Haiku 4.5 accepts them, but the
   word-steering habit is portable.)
2. **Stable context first, the specific question last.** Better for the reader
   and prompt-cache friendly.
3. **Every prompt ends with a success criterion.** "Done means…" — the single
   highest-leverage addition across every model.
4. **Depth is set by effort, not a token budget** on the frontier three;
   recommend adaptive thinking when reasoning is wanted (Haiku 4.5 has no effort —
   keep its prompts simple instead of dialing thinking).

## Efficiency rules (the "more efficient" lever)

The coach optimizes for the cheapest correct result, not the biggest model:

1. **Recommend the cheapest model that clears the bar** (see the recommender).
   Prices per MTok in/out: Haiku 4.5 $1/$5 · Sonnet 5 $3/$15 (intro $2/$10 through
   Aug 2026) · Opus 4.8 $5/$25 · Fable 5 $10/$50.
2. **Strip the ramble's redundancy** before rewriting — drop restatements,
   filler, and the same ask phrased three ways.
3. **Match effort to difficulty.** Don't request `xhigh`/`max` for routine work;
   higher effort spends tokens and latency for reasoning the task doesn't need.
4. **Keep the rewritten prompt tight** — a shorter prompt that still carries
   scope + acceptance test beats a padded one.
5. **Front-load stable/reusable context** so repeated runs hit the prompt cache.

---

## Quick contrast table (what the coach changes per model, same ramble in)

| Dimension | Haiku 4.5 | Sonnet 5 | Opus 4.8 | Fable 5 |
|---|---|---|---|---|
| Level of detail | High — one task, exact output | High — spell out scope | High — full spec up front | Low — goal + why, no steps |
| Biggest risk if under-specified | Guesses / stays shallow | Misses implied scope | Asks too many questions | Over-elaborates, wanders |
| Add trigger lines for tools? | Keep simple; escalate instead | Only if thinking off | Yes — and in tool descriptions | Encourage, don't micromanage |
| Autonomy instruction | n/a | Not usually needed | Yes — "don't ask on small stuff" | Yes — "report and stop" |
| Verbosity control | Ask for the shape you want | Positive examples | Silence-default if chatty | Communication-style section |
| Effort suggestion | none (unsupported) | high (xhigh for hard coding) | high (don't reflex-xhigh) | high (low/med often enough) |
| Cost per MTok (in/out) | $1 / $5 | $3 / $15 | $5 / $25 | $10 / $50 |
| Reach for it when… | simple/high-volume | most tasks (default) | long autonomous work | hardest reasoning only |
