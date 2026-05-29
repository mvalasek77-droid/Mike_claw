# AIMarketplaceTests

Deterministic XCTest suite for the AI Editor pipeline.

## What's covered

- **`AIEditorTests`** — adversarial cases the audit found in the old scorer:
  - 110 words of lorem ipsum + fake tool names + $4.99 price MUST fail < 85
  - Metadata-only path (no real bytes) is capped at 60
  - Synonym-swapped catalogue title is flagged as derivative
  - Silent music submission fails
  - Zero-duration video fails
  - Identical / near-identical cover pHash flags as copycat
  - Famous-IP names in title / synopsis / manuscript body raise copyright_risk
  - Autopilot is blocked when content is missing, copycat sim is high, or
    copyright_risk is high — even at a passing overall score
  - A real strong novel / music master / film still passes 85 (sanity)
- **`ContentAnalysisTests`** — verifies the underlying measurements
  (lorem-ipsum vocabulary, trigram repetition, Hamming distance, broken-video
  detection) the Editor depends on.

## Running

The test target is declared in `../project.yml`. After editing the spec, run

```bash
xcodegen generate
```

from the `AIMarketplace/` directory to regenerate the Xcode project with the
test target wired in. Then run `xcodebuild test` or use the Tests scheme in
Xcode. (The committed `.xcodeproj` in this branch predates the test target —
regenerate before running.)

## Why these tests use synthetic `ReviewAnalysis` payloads

`AVFoundation` decoders and `NaturalLanguage` embeddings need iOS or Mac
Catalyst frameworks at runtime. Rather than ship fixture WAV/MP4 files (slow,
fragile across CI), the tests construct synthetic `ContentAnalysis.*Report`
values that mirror what the real pipelines produce, then feed them straight to
`AIEditor.review`. The `ContentAnalysis.analyseText` calls in
`AIEditorTests` use the framework live — that's safe because
`NaturalLanguage` is available in the unit-test runtime and only operates on
in-memory strings.
