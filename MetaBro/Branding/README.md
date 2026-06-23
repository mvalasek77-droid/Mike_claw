# MetaBro Brand & Avatar System

**Slogan:** *The Man Cave of the Internet.*

## Logo & app icon
- **Mark:** a Liquid-Glass rounded square with a bold monogram **M** whose centre
  forms an upward chevron — it reads as the letter *and* an upvote / growth arrow
  (the Reddit half), in MetaBro green.
- Files: `icon.svg` (rounded, marketing), `icon_square.svg` (full-bleed, the iOS
  asset), `logo.svg` (wordmark lockup). Rendered PNGs alongside.
- The app icon is wired into `MetaBro/MetaBro/Assets.xcassets/AppIcon.appiconset`.

Regenerate:
```bash
pip install cairosvg
python tools/metabro_assets/generate_brand.py
```

## Generative avatars (daily-refreshed)
Every user and Bro-hood gets a unique, deterministic, generative avatar. The
seed mixes the identity (handle / slug) with the **current date**, so the whole
gallery subtly regenerates **once per day**.

- Generator: `tools/metabro_assets/generate_avatars.py` → `avatars/<id>.png`.
- Previews: `tools/metabro_assets/generate_gallery.py` → `previews/gallery.png`,
  `previews/rotation.png`.
- Daily refresh: `.github/workflows/avatars-daily.yml` (cron `0 6 * * *`)
  regenerates and commits the gallery.

### Backends
- **Procedural (default):** layered Liquid-Glass art rendered locally with
  `cairosvg`. No API key — hermetic and free, so CI works out of the box.
- **AI image model (optional):** set `METABRO_IMAGE_API_URL`
  (+ `METABRO_IMAGE_API_KEY`) and the generator POSTs a per-identity prompt to a
  diffusion endpoint, falling back to procedural art on any error. Wire the
  secrets into the daily workflow's `env:` to switch the whole flow to real AI art.

### Consuming in the app
`AvatarCatalog` (in `MetaBro/Core`) maps a user handle / community slug to its
published avatar URL. The `UserAvatar` and `CommunityAvatar` SwiftUI components
load these via `AsyncImage` (with a tinted-monogram fallback) and are wired into
the **feed posts, profile, stories, and conversation list**. The cron refreshes
the images daily, so the app picks up new art with no release. Point
`AvatarCatalog.base` at a CDN in production.

## Daily content feed
`tools/metabro_assets/generate_content.py` generates a fresh, date-seeded feed of
posts each day in the app's wire format (`FeedPageDTO` / `PostDTO`), with every
author and Bro-hood carrying its daily avatar URL. Output:
`content/feed-latest.json` (+ a dated copy). `LiveFeedService` can serve this
directly — point the API base at the published `content/` path (or a CDN) and the
feed updates daily with no release. The daily workflow regenerates avatars **and**
content together.
