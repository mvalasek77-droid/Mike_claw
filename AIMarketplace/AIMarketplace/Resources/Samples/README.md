# Bundled content

These are the real, creator-supplied works that make up the live catalogue.
Each `MediaItem` in `SampleData.swift` references a file here by slug via
`coverAssetName` (poster) and `mediaFileName` (audio / manuscript). They're
resolved at runtime by `ContentResolver`.

| Slug | Poster | Media |
|------|--------|-------|
| `the-odyssey-protocol` | `.jpg` | `.txt` (70k-word manuscript, shown in the reader) |
| `its-a-swifty-world-after-all` | `.jpg` | `.mp3` |
| `curves-like-keisha` | `.jpg` | `.mp3` |
| `push-up-bra` | `.jpg` | `.mp3` |

## Adding another work
1. Drop the media (`.mp3` / `.m4a` / `.mp4` / `.txt`) and a poster (`.jpg`) here,
   named with a lowercase, hyphenated slug.
2. Add a `MediaItem` to `SampleData.catalog()` with matching `coverAssetName`
   and `mediaFileName`.
3. Re-run `xcodegen generate` so the files are added to the target.

Posters can also be regenerated programmatically (gradient + title) — see the
session history — or replaced with your own artwork at the same filename.
