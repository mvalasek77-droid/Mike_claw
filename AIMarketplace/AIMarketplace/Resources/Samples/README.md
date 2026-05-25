# Sample content — drop your files here

The app plays **real** audio/video and shows **real** cover art the moment a
matching file exists in this folder. Until then it falls back to a procedural
poster and a simulated playhead, so the app always runs.

## How to add a file

You have three options:

1. **In Xcode (easiest):** after running `xcodegen generate`, drag your files
   into the `Resources/Samples` group in the Project navigator. Tick
   *"Copy items if needed"* and your app target under *"Add to targets"*.
2. **In git:** copy the file into this folder
   (`AIMarketplace/AIMarketplace/Resources/Samples/`), then
   `git add` + commit + push. Re-run `xcodegen generate` so the new file is
   added to the target.
3. **Custom art for a title you publish in-app:** just pick it in the new
   "Cover Art" step of the publishing flow — no files needed.

## Naming convention

Each seed title resolves art/media by a **slug** of its name (lowercased,
spaces & punctuation → `-`). Filename must match the slug.

| Accepted | Extensions (first match wins) |
|----------|-------------------------------|
| Cover art (all types) | `.jpg` `.jpeg` `.png` `.heic` |
| Music master | `.m4a` `.mp3` `.aac` `.wav` |
| Film file | `.mp4` `.mov` `.m4v` |

(Novels use the paginated reader and need only a cover.)

### Expected filenames for the seed catalogue

**Films** (cover + video)
- `echoes-of-tomorrow`
- `the-last-lighthouse`
- `neon-province`
- `salt-static`

**Music** (cover + audio)
- `midnight-cartography`
- `paper-cathedrals`
- `gravity-optional`
- `songs-for-an-empty-house`

**Novels** (cover only)
- `the-cartographer-of-silence`
- `gravewater`
- `saffron-steel`
- `quietly-the-machines`
- `the-inheritance-algorithm`

Example: dropping `midnight-cartography.jpg` + `midnight-cartography.m4a`
makes that album show its real cover everywhere and play your audio in the
dedicated player.
