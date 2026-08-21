# boxcall.com landing page

Static single-page site. No build step — open `index.html`.

## Structure

- `index.html` — hero, how-it-works, pricing, FAQ, footer CTAs
- `style.css` — dark theme system with orange accent, tier gradients, phone mockup
- No JS. No tracking. No third-party fonts (system stack).

## Deploy

Drop into any static host (Vercel, Netlify, Cloudflare Pages, S3+CloudFront). No env config required.

## What still needs adding

- `terms.html` + `privacy.html` — mirror the in-app copy from `BoxCall/BoxCall/Views/LegalView.swift`
- `og.png` — 1200×630 social preview (currently `<meta og:image>` points at a placeholder)
- Real App Store link once approved — replace the two `https://apps.apple.com/app/boxcall` hrefs
- Newsletter capture on the footer CTA (Substack, Buttondown, or a simple form pointing at the FastAPI backend)
- Analytics — Plausible or Fathom recommended; nothing that requires a cookie banner
