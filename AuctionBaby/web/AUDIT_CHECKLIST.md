# Auction Baby Web — Deep Audit Test Checklist

> Test each item in two modes: **DEMO** (config.js URLs blank) and **LIVE** (config.js populated, Workers deployed). Mark ✅ pass, ❌ fail, ⚠️ partial.

---

## 0  Environment Pre-flight

| # | Check | Demo | Live |
|---|-------|------|------|
| 0.1 | `index.html` loads without console errors | | |
| 0.2 | `config.js`, `api.js`, `app.js` all loaded (check Network tab — no 404) | | |
| 0.3 | Service worker registered (`navigator.serviceWorker.controller` truthy after reload) | | |
| 0.4 | Manifest linked — Lighthouse → Installable or `beforeinstallprompt` fires | | |
| 0.5 | HTTPS served (required for SW + SIWA + Web Push) | | |
| 0.6 | `window.AB_LIVE` is `false` in Demo, `true` in Live | | |
| 0.7 | No mixed-content warnings in console | | |

---

## 1  Onboarding

| # | Check | Demo | Live |
|---|-------|------|------|
| 1.1 | First visit shows onboarding (no hash, `S.registered === false`) | | |
| 1.2 | Both role cards render: "I'm bidding" and "I'm a lot" | | |
| 1.3 | Tapping a role highlights it (gold border + "Selected" pill) | | |
| 1.4 | Tapping "Step onto the floor" without selecting a role → toast "Pick a side first." | | |
| 1.5 | Submitting with empty name → toast "Add your name." | | |
| 1.6 | Submitting with age < 18 → toast "You must be 18 or older." | | |
| 1.7 | Valid submission (name + age ≥ 18 + role) → navigates to Floor/Bids | | |
| 1.8 | After submission, `S.registered === true` in localStorage | | |
| 1.9 | City field is optional — blank city should not block onboarding | | |
| 1.10 | **LIVE**: "Sign in with Apple" button visible when `APPLE_SERVICE_ID` set | | |
| 1.11 | **LIVE**: Apple sign-in popup opens, returns token, toast "Signed in with Apple." | | |
| 1.12 | **LIVE**: Apple-provided name pre-fills the Name field if empty | | |
| 1.13 | **LIVE**: After Apple sign-in, `SIGNED_IN()` returns true | | |
| 1.14 | **LIVE**: Profile saved to auth Worker on submit (`saveProfile` called) | | |
| 1.15 | **DEMO**: Apple button hidden (no APPLE_SERVICE_ID) | | |

---

## 2  The Floor (Bidder / Man Role)

| # | Check | Demo | Live |
|---|-------|------|------|
| 2.1 | 8 demo women render on first load (Serena, Mara, Priya, Sloane, Noor, Valentina, Jade, Amber) | | |
| 2.2 | "Lot of the day" banner on the first (hero) card | | |
| 2.3 | Hero card has gold border + gold shadow (`lot.hero` class) | | |
| 2.4 | Gavel balance shown in top-right pill (starts at 750) | | |
| 2.5 | Ticker bar cycles between 3 messages every ~6 seconds | | |
| 2.6 | Live dot pulses (`.dot` red + shadow) | | |
| 2.7 | Each card shows: name, age, city chip, starting bid chip | | |
| 2.8 | Gradient avatars render with correct initials (2-letter max, uppercase) | | |
| 2.9 | **LIVE**: `syncFloor()` replaces demo data with server profiles | | |
| 2.10 | **LIVE**: Photos display when `photos[0].url` present in server response | | |
| 2.11 | Tapping a card navigates to `#/lot/<id>` (lot detail) | | |
| 2.12 | Tab bar shows Floor/Matches/Store/You — Floor highlighted | | |
| 2.13 | Tab bar fixed at bottom, doesn't scroll with content | | |

---

## 3  Lot Detail

| # | Check | Demo | Live |
|---|-------|------|------|
| 3.1 | Back button ("‹ Floor") returns to `#/floor` | | |
| 3.2 | Full avatar (gradient or photo), name, age, verified badge, city, starting bid | | |
| 3.3 | "About" card shows bio text | | |
| 3.4 | Prompt cards render each icebreaker | | |
| 3.5 | "Place a bid" button present | | |
| 3.6 | Navigating to a non-existent lot ID redirects to floor | | |
| 3.7 | Gavel balance shown in header pill | | |

---

## 4  Bid Sheet (Modal)

| # | Check | Demo | Live |
|---|-------|------|------|
| 4.1 | Tapping "Place a bid" opens bottom sheet overlay | | |
| 4.2 | Sheet shows small avatar + "Bidding on [name]" + floor price | | |
| 4.3 | Initial amount = starting bid (e.g. $300 for Serena) | | |
| 4.4 | +$50, +$100, +$1,000, +$10,000 chips increment the amount | | |
| 4.5 | "Reset" chip returns amount to starting bid | | |
| 4.6 | Amount display uses gold gradient text (`.amount` class) | | |
| 4.7 | Large amounts formatted with commas ($10,000 not $10000) | | |
| 4.8 | Note textarea placeholder: "Why you? Make the bid count." | | |
| 4.9 | "Place $X bid" button text updates as amount changes | | |
| 4.10 | Clicking outside the panel (on overlay) closes the sheet | | |
| 4.11 | Disclosure text visible about bid = date budget | | |
| 4.12 | **DEMO**: Placing bid → celebration screen (always accepts) | | |
| 4.13 | **LIVE**: `API.placeBid(lotId, amount, note)` called with correct values | | |
| 4.14 | **LIVE**: Toast "Bid placed — you'll be notified if she accepts." on success | | |
| 4.15 | **LIVE**: Toast shows error message on failure | | |

---

## 5  Celebration Screen

| # | Check | Demo | Live |
|---|-------|------|------|
| 5.1 | Full-screen dark overlay with "SOLD!" in gold gradient text | | |
| 5.2 | Shows matched woman's name + winning bid amount | | |
| 5.3 | "Say hello" button navigates to `#/chat/<matchId>` | | |
| 5.4 | Tapping anywhere else dismisses the overlay (stays on floor) | | |
| 5.5 | Match added to `S.matches` with the woman's opener message | | |

---

## 6  Incoming Bids (Woman Role)

| # | Check | Demo | Live |
|---|-------|------|------|
| 6.1 | Registering as "I'm a lot" → shows "Your bids" screen instead of Floor | | |
| 6.2 | 4 demo suitors render (Marcus, Julian, Theo, Dominic) | | |
| 6.3 | Each bid card shows: avatar, name, age, bid amount in gold, note | | |
| 6.4 | "Accept" button (rose) and "Pass" button (ghost) on each card | | |
| 6.5 | Accept → celebration screen → match created with "You're in. Where are we going? 🍸" | | |
| 6.6 | Pass → bid removed from list, toast "Passed." | | |
| 6.7 | All bids declined → "No bids yet — sit tight" card | | |
| 6.8 | Tab bar shows "Bids" instead of "Floor" for women | | |
| 6.9 | Returning to app with 0 incoming (demo) → reseeds 4 suitors | | |
| 6.10 | **LIVE**: `syncIncoming()` loads from `API.incomingBids()` | | |
| 6.11 | **LIVE**: Accept calls `API.acceptBid(id)` then syncs matches | | |
| 6.12 | **LIVE**: Decline calls `API.declineBid(id)` | | |

---

## 7  Matches List

| # | Check | Demo | Live |
|---|-------|------|------|
| 7.1 | Navigate via tab bar "Matches" → `#/matches` | | |
| 7.2 | Each match shows: avatar, name, last message preview, bid amount pill | | |
| 7.3 | Matches sorted by `lastTs` (most recent activity first) | | |
| 7.4 | Unread matches show gold dot (`.udot`) instead of amount pill | | |
| 7.5 | Unread count badge on Matches tab icon (red badge, e.g. "2") | | |
| 7.6 | No matches → "No matches yet. Win a bid on the floor." card | | |
| 7.7 | Tapping a match navigates to `#/chat/<id>` | | |
| 7.8 | Photo messages preview as "📷 Photo" text (not blank) — verify in `last.text` | | |
| 7.9 | **LIVE**: `syncMatches()` populates from `API.matches()` | | |
| 7.10 | Long match name truncated with ellipsis in preview row | | |

---

## 8  Chat

| # | Check | Demo | Live |
|---|-------|------|------|
| 8.1 | Back button ("‹") returns to `#/matches` | | |
| 8.2 | Other person's name + small avatar in header | | |
| 8.3 | Messages render as bubbles: gold for me, dark for them | | |
| 8.4 | System messages centered, faint style | | |
| 8.5 | Composer at bottom: text input + gold send button | | |
| 8.6 | Typing a message + Enter key sends | | |
| 8.7 | Typing a message + tapping ↑ button sends | | |
| 8.8 | Empty message → nothing sent (no empty bubble) | | |
| 8.9 | Sent message appears immediately as "me" bubble | | |
| 8.10 | Chat scrolls to bottom on load and after sending | | |
| 8.11 | **DEMO**: Bot replies after ~1.1–2s delay with random response | | |
| 8.12 | **DEMO**: "•••" typing indicator shows during delay | | |
| 8.13 | Read receipts: "Delivered" after my last message, "Seen" after demo reply | | |
| 8.14 | Opening a chat with `m.unread === true` clears the unread flag | | |
| 8.15 | Report flag button (⚑) visible in header | | |
| 8.16 | **LIVE**: `API.sendMessage(id, text)` called on send | | |
| 8.17 | **LIVE**: `API.markSeen(id)` called when chat opens | | |
| 8.18 | **LIVE**: Send failure → toast "Send failed: …" | | |

### 8A  Reactions

| # | Check | Demo | Live |
|---|-------|------|------|
| 8A.1 | Double-tap a bubble → ❤️ reaction badge appears | | |
| 8A.2 | Double-tap same bubble again → reaction toggles off | | |
| 8A.3 | Long-press a bubble (~420ms) → emoji picker bar appears | | |
| 8A.4 | Picker shows: ❤️ 😂 😮 👍 🔥 | | |
| 8A.5 | Tapping a picker emoji → reaction applied, picker dismissed | | |
| 8A.6 | Reaction badge position: left of "me" bubbles, right of "them" bubbles | | |
| 8A.7 | Tapping the overlay (outside picker row) dismisses it | | |
| 8A.8 | **LIVE**: `API.react(matchId, messageId, emoji)` called | | |

### 8B  Reserve the Date (Bidder Only)

| # | Check | Demo | Live |
|---|-------|------|------|
| 8B.1 | "Reserve" chip visible in chat header for bidder role only | | |
| 8B.2 | Not visible for woman role | | |
| 8B.3 | Tapping "Reserve" opens bottom sheet with tier options | | |
| 8B.4 | Tiers shown: $10, $15, $25, $50, $100 | | |
| 8B.5 | Sheet text explains: booking fee to Auction Baby, not to her | | |
| 8B.6 | **DEMO**: Tapping a tier → "Demo: date reserved." toast + chip changes to "✓ Reserved" | | |
| 8B.7 | **LIVE**: Calls `API.reserveDate(matchId, amountCents)` | | |
| 8B.8 | **LIVE**: Successful non-redirect → marks reserved locally | | |
| 8B.9 | **LIVE**: Redirect to Stripe Checkout occurs when `data.url` returned | | |
| 8B.10 | After reserving, "Reserve" chip replaced with "✓ Reserved" (green/on style) | | |
| 8B.11 | Clicking outside sheet overlay dismisses it | | |

---

## 9  Report & Block

| # | Check | Demo | Live |
|---|-------|------|------|
| 9.1 | ⚑ button in chat header opens report sheet | | |
| 9.2 | Sheet shows: "Block [name] and report to moderation." | | |
| 9.3 | Five reason chips: Inappropriate, Harassment, Fake profile, Spam, Other | | |
| 9.4 | Tapping a reason → match removed from `S.matches`, navigates to `#/matches` | | |
| 9.5 | Toast "Reported & blocked." | | |
| 9.6 | "Cancel" button dismisses sheet without action | | |
| 9.7 | Clicking outside panel dismisses sheet | | |
| 9.8 | **LIVE**: `API.blockUser(otherId, reason)` called | | |
| 9.9 | **LIVE**: `API.reportUser(otherId, reason, "chat")` called | | |
| 9.10 | Blocked match no longer appears in matches list | | |

---

## 10  Store

| # | Check | Demo | Live |
|---|-------|------|------|
| 10.1 | Navigate via tab bar → `#/store` | | |
| 10.2 | Gavel balance pill in header | | |
| 10.3 | Four Gavel packs: Handful 1K/$4.99, Stack 5K/$19.99, Chest 14K/$49.99, Vault 30K/$99.99 | | |
| 10.4 | "BEST VALUE" pill on Vault (last pack) | | |
| 10.5 | Three Pass tiers: Paddle $19.99/mo, Reserve $39.99/mo, Black Card $99.99/mo | | |
| 10.6 | Pass descriptions match perk tiers correctly | | |
| 10.7 | Disclosure text about Stripe + Gavels | | |
| 10.8 | **DEMO**: Buying Gavels → wallet increments + toast "Demo: +X Gavels (configure Stripe for live)." | | |
| 10.9 | **DEMO**: Subscribing to Pass → toast "Demo: [tier] Pass active (configure Stripe for live)." | | |
| 10.10 | **DEMO**: Store page re-renders with updated balance after purchase | | |
| 10.11 | **LIVE**: Gavels → `API.me()` → `API.buyGavels(packId, userId)` → redirect to Stripe Checkout | | |
| 10.12 | **LIVE**: Pass → `API.me()` → `API.subscribe(passId, userId)` → redirect to Stripe Checkout | | |
| 10.13 | **LIVE**: Pack IDs map correctly: `gavels_handful`, `gavels_stack`, `gavels_chest`, `gavels_vault` | | |
| 10.14 | **LIVE**: Pass IDs map correctly: `pass_paddle`, `pass_reserve`, `pass_blackcard` | | |
| 10.15 | **LIVE**: Checkout failure → toast "Checkout: …" or "Subscribe: …" with error | | |
| 10.16 | Returning with `#/store?paid=1` → toast "Payment complete — Gavels added." | | |

---

## 11  You (Profile / Settings)

| # | Check | Demo | Live |
|---|-------|------|------|
| 11.1 | Navigate via tab bar → `#/you` | | |
| 11.2 | Profile card shows: avatar (gradient or photo), name, age, city, role label, Gavel balance | | |
| 11.3 | "Add a photo" button (or "Change photo" if photo exists) | | |
| 11.4 | Photo picker opens file picker for image/* | | |
| 11.5 | Selected image downscaled to ≤1024px, JPEG 0.82 quality | | |
| 11.6 | **DEMO**: Photo saved as dataURL in `S.me.photo`, profile re-renders with photo | | |
| 11.7 | **LIVE**: `API.uploadPhoto(blob)` called; server URL stored on success | | |
| 11.8 | **LIVE**: Upload failure → falls back to local dataURL + toast with error | | |
| 11.9 | "Open the Store" button navigates to `#/store` | | |
| 11.10 | **LIVE + VAPID**: "Enable notifications" button visible | | |
| 11.11 | **LIVE + VAPID**: Tapping notifications → permission prompt → toast "Notifications on." | | |
| 11.12 | **LIVE + VAPID**: Permission denied → toast "Notifications: Permission denied" | | |
| 11.13 | **DEMO**: No notifications button (no VAPID key) | | |
| 11.14 | **LIVE**: "Sign out" button visible when signed in | | |
| 11.15 | Sign out → clears session token, resets `S.registered`, shows onboarding | | |
| 11.16 | "Reset account" → confirm dialog → wipes localStorage, reseeds floor, shows onboarding | | |
| 11.17 | **LIVE**: "Delete account permanently" button visible | | |
| 11.18 | Delete → confirm dialog → calls `API.deleteAccount()` → full wipe + onboarding | | |
| 11.19 | Declining confirm dialogs does nothing (no state change) | | |

---

## 12  Photo Upload + Display

| # | Check | Demo | Live |
|---|-------|------|------|
| 12.1 | Profile photo renders as round-cornered image replacing gradient avatar | | |
| 12.2 | Floor cards show photo when present (lot `photo` field) | | |
| 12.3 | Lot detail shows photo in art area | | |
| 12.4 | Match list avatars show photos when available | | |
| 12.5 | Chat header avatar shows photo | | |
| 12.6 | Images use `loading="lazy"` attribute | | |
| 12.7 | Images use `object-fit: cover` within avatar container | | |
| 12.8 | Large photos (> 1024px) are downscaled before upload | | |
| 12.9 | Transparent images → JPEG conversion doesn't crash (white background expected) | | |

---

## 13  PWA / Offline / Install

| # | Check | iOS Safari | Chrome | Firefox |
|---|-------|------------|--------|---------|
| 13.1 | Service worker installs and activates on first load | | | |
| 13.2 | "auctionbaby-v2" cache created with all 7 assets | | | |
| 13.3 | Refresh while offline → app shell loads from cache | | | |
| 13.4 | Navigate between screens while offline (demo mode) | | | |
| 13.5 | API calls fail silently in demo mode (no crashes) | | | |
| 13.6 | iOS Safari: Share → Add to Home Screen works | | | |
| 13.7 | Opens as standalone app (no Safari UI) from home screen | | | |
| 13.8 | `theme-color` matches (`#0d0b08`) in status bar | | | |
| 13.9 | Chrome: install prompt fires (or Lighthouse installable) | | | |
| 13.10 | Cache updates when new SW version deployed (v2 → v3) | | | |
| 13.11 | Old caches cleaned up on activate | | | |
| 13.12 | Non-GET requests (API POSTs) bypass cache (pass through) | | | |

---

## 14  Web Push (Client-Side Only — Server Not Yet Deployed)

| # | Check | Demo | Live |
|---|-------|------|------|
| 14.1 | **LIVE**: `enableWebPush()` requests Notification permission | | |
| 14.2 | **LIVE**: On grant → subscribes via PushManager | | |
| 14.3 | **LIVE**: Subscription POSTed to `/devices/register-web` | | |
| 14.4 | `sw.js` push handler parses JSON payload | | |
| 14.5 | Notification shows `title` (or fallback "Auction Baby") and `body` | | |
| 14.6 | `notificationclick` navigates/focuses the app window | | |
| 14.7 | `notificationclick` opens correct `data.url` (deep link via hash) | | |
| 14.8 | Push with malformed data doesn't crash SW (try/catch around `e.data.json()`) | | |

---

## 15  Sign in with Apple (Web)

| # | Check | Live Only |
|---|-------|-----------|
| 15.1 | Apple JS SDK loads from CDN when button tapped | |
| 15.2 | Popup appears with Apple sign-in UI | |
| 15.3 | Successful sign-in → POST `/auth/apple` with `identityToken` | |
| 15.4 | Session token stored in `localStorage.auctionbaby.web.session` | |
| 15.5 | `fullName` sent when Apple provides it (first sign-in only) | |
| 15.6 | Token persists across page reloads | |
| 15.7 | Auth Worker accepts web token audience (`WEB_CLIENT_ID` in multi-audience check) | |
| 15.8 | Failed Apple sign-in → toast with error message, no crash | |
| 15.9 | Apple JS load failure → toast "Apple JS failed to load" | |
| 15.10 | Sign-in from onboarding screen pre-fills name if returned by Apple | |

---

## 16  Landing Page (`landing.html`)

| # | Check | Mobile | Desktop |
|---|-------|--------|---------|
| 16.1 | Page loads, no console errors | | |
| 16.2 | Hero: icon, kicker, h1 "Bid what a date is worth.", subtitle, CTA buttons | | |
| 16.3 | "Open Auction Baby" links to `./index.html` | | |
| 16.4 | "How it works" anchors to `#how` section | | |
| 16.5 | 4 step cards: Step onto the floor, Place a bid, She accepts, Plan the date | | |
| 16.6 | 3 "Why it's different" cards | | |
| 16.7 | Pink compliance note about bid = promise, not payment | | |
| 16.8 | Footer: Privacy, Terms, Support links point to GitHub Pages docs | | |
| 16.9 | Copyright year auto-filled by JS | | |
| 16.10 | Responsive: cards stack single-column on mobile | | |
| 16.11 | Responsive: grid fills width on desktop | | |
| 16.12 | Add to Home Screen instruction visible on mobile | | |

---

## 17  Responsive / Mobile

| # | Check | iPhone SE | iPhone 15 | Android | iPad |
|---|-------|-----------|-----------|---------|------|
| 17.1 | Max-width 520px centered on large screens | | | | |
| 17.2 | No horizontal scroll on any screen | | | | |
| 17.3 | Tab bar sticks to bottom, respects `safe-area-inset-bottom` | | | | |
| 17.4 | Composer input respects `safe-area-inset-bottom` | | | | |
| 17.5 | Bottom sheet panels respect `safe-area-inset-bottom` | | | | |
| 17.6 | Text remains readable at minimum viewport (320px width) | | | | |
| 17.7 | Tap targets ≥ 44px (buttons, chips, tab bar items) | | | | |
| 17.8 | No content hidden behind notch or Dynamic Island | | | | |
| 17.9 | Keyboard doesn't cover composer input when typing | | | | |
| 17.10 | `overscroll-behavior-y: none` prevents pull-to-refresh bounce | | | | |

---

## 18  Data Persistence (localStorage)

| # | Check |
|---|-------|
| 18.1 | Full state stored under `auctionbaby.web.v1` key |
| 18.2 | Session token under `auctionbaby.web.session` (separate key) |
| 18.3 | Closing and reopening browser → state preserved (registered, matches, wallet) |
| 18.4 | Corrupted localStorage JSON → `fresh()` called, no crash |
| 18.5 | Missing localStorage item → `fresh()` returns default state |
| 18.6 | Private/incognito mode → app works (localStorage available but ephemeral) |
| 18.7 | `save()` called after every state mutation |
| 18.8 | Reset account clears `auctionbaby.web.v1` and reseeds |
| 18.9 | Sign out clears session token but preserves app state (returns to onboarding) |

---

## 19  Security & XSS

| # | Check |
|---|-------|
| 19.1 | All user-generated content rendered via `esc()` (HTML entity escaping) |
| 19.2 | Name, city, bio, note, message text all escaped before `innerHTML` |
| 19.3 | `esc()` covers `&`, `<`, `>`, `"` |
| 19.4 | Photo URLs injected via `esc()` into `src` attributes |
| 19.5 | No `eval()`, `Function()`, or `document.write()` in app code |
| 19.6 | API responses parsed with `JSON.parse()` (not eval) |
| 19.7 | `Content-Type: application/json` set on all API requests |
| 19.8 | Token sent only via `Authorization: Bearer` header (not URL params) |
| 19.9 | No credentials stored in config.js (only public URLs and public VAPID key) |
| 19.10 | Photo upload sends raw binary with `Content-Type: image/jpeg` (no JSON injection) |
| 19.11 | `encodeURIComponent` used for query params (`location`, `matchId`, `userId`) |

---

## 20  Navigation & Hash Routing

| # | Check |
|---|-------|
| 20.1 | `#/floor` → Floor (or Bids for woman) |
| 20.2 | `#/lot/<id>` → Lot detail |
| 20.3 | `#/matches` → Matches list |
| 20.4 | `#/chat/<id>` → Chat screen |
| 20.5 | `#/store` → Store screen |
| 20.6 | `#/you` → Profile/settings |
| 20.7 | Unknown hash → defaults to floor |
| 20.8 | Browser back/forward works between screens |
| 20.9 | Direct URL with hash loads correct screen (deep link) |
| 20.10 | Empty hash on registered user → floor |
| 20.11 | Empty hash on unregistered user → onboarding |
| 20.12 | `#/lot/<invalid-id>` → redirects to floor (lot not found) |
| 20.13 | `#/chat/<invalid-id>` → redirects to matches (match not found) |

---

## 21  Edge Cases & Error Handling

| # | Check |
|---|-------|
| 21.1 | Rapidly tapping "Place bid" multiple times → only one celebration/match created |
| 21.2 | Accept same bid twice (race condition) → no duplicate match |
| 21.3 | Send message to a match that was just reported/blocked → graceful (no crash) |
| 21.4 | Switching roles: reset → re-register as opposite role → correct UI shown |
| 21.5 | Very long name (50+ chars) → truncated gracefully in UI, no layout break |
| 21.6 | Very long message → wraps properly in bubble, doesn't overflow |
| 21.7 | Special characters in name/bio/messages (emoji, unicode, quotes) → rendered correctly |
| 21.8 | Network error during live API call → caught, toast shown, no crash |
| 21.9 | `API.floor()` returns unexpected shape → caught, demo floor preserved |
| 21.10 | 0 matches + 0 incoming → empty states render properly |
| 21.11 | Wallet at 0 → still able to navigate, bid amounts still display |
| 21.12 | Multiple tabs open simultaneously → localStorage changes reflected on focus |

---

## 22  Live API Contract Verification

> These validate the mapper functions against actual Worker responses.

| # | Check | Notes |
|---|-------|-------|
| 22.1 | `GET /users/floor` → `mapLot` fields: `userId`, `name`, `age`, `location`, `bio`, `photos`, `prompts`, `startingBid`, `verified`, `hue` | |
| 22.2 | `GET /bids/incoming` → each bid has: `id`, `man.name`, `age`, `amount`/`bidAmount`, `note` | |
| 22.3 | `GET /matches` → each match has: `id`, `other.name`, `other.userId`, `amount`, `seenByOther`, `unreadCount`, `updatedAt`, `messages[]` | |
| 22.4 | `GET /me` → returns `id`/`userId` for Stripe checkout calls | |
| 22.5 | `POST /bids` → accepts `{ lotId, amount, note }` | |
| 22.6 | `POST /bids/:id/accept` → returns success | |
| 22.7 | `POST /bids/:id/decline` → returns success | |
| 22.8 | `POST /matches/:id/messages` → accepts `{ text }` | |
| 22.9 | `POST /matches/:id/mark-seen` → returns success | |
| 22.10 | `POST /matches/:id/messages/:mid/react` → accepts `{ emoji }` | |
| 22.11 | `POST /me/photos` → binary JPEG, returns `{ photo: { url } }` or similar | |
| 22.12 | `PUT /me/profile` → accepts `{ name, location, role }` | |
| 22.13 | `POST /me/blocks` → accepts `{ userId, reason }` | |
| 22.14 | `POST /me/reports` → accepts `{ userId, reason, context }` | |
| 22.15 | `POST /checkout` → returns `{ url }` (Stripe redirect) | |
| 22.16 | `POST /subscribe` → returns `{ url }` (Stripe Billing redirect) | |
| 22.17 | `POST /reserve/checkout` → returns `{ url }` or `{ reserved: true }` | |
| 22.18 | `POST /auth/apple` → accepts `{ identityToken, fullName }`, returns `{ token, user }` | |
| 22.19 | `DELETE /me` → account deletion succeeds | |
| 22.20 | `POST /devices/register-web` → accepts `{ subscription: { endpoint, keys } }` | |

---

## 23  Stripe Checkout Flow (End-to-End)

| # | Check |
|---|-------|
| 23.1 | Gavels: clicking a pack → redirects to Stripe Checkout with correct amount |
| 23.2 | Stripe Checkout shows correct product name and price |
| 23.3 | Successful payment → redirects to `CHECKOUT_SUCCESS_URL` |
| 23.4 | Cancel payment → redirects to `CHECKOUT_CANCEL_URL` |
| 23.5 | `?paid=1` in return URL → toast "Payment complete — Gavels added." |
| 23.6 | Webhook processed: Gavel balance updated in Worker (verify via API.balance if wired) |
| 23.7 | Pass: clicking Subscribe → Stripe Checkout in subscription mode |
| 23.8 | Recurring subscription created in Stripe dashboard |
| 23.9 | Pass status queryable via `API.subscriptionStatus(userId)` |
| 23.10 | Reserve: clicking a tier → Stripe Checkout or instant reservation |

---

## 24  CI Pipeline (`.github/workflows/web-ci.yml`)

| # | Check |
|---|-------|
| 24.1 | `node --check` passes on `app.js`, `api.js`, `config.js`, `sw.js` |
| 24.2 | Manifest JSON is valid (parseable) |
| 24.3 | CI runs on push to web/ directory |
| 24.4 | CI failure on syntax error in any JS file |

---

## 25  Cross-Browser Compatibility

| # | Check | Safari 17+ | Chrome 120+ | Firefox 120+ | Samsung Internet |
|---|-------|------------|-------------|---------------|------------------|
| 25.1 | App loads and renders correctly | | | | |
| 25.2 | CSS custom properties (`:root` vars) applied | | | | |
| 25.3 | `backdrop-filter: blur()` on tab bar + composer | | | | |
| 25.4 | `aspect-ratio` on avatar + lot art | | | | |
| 25.5 | `background-clip: text` on gold gradient text | | | | |
| 25.6 | `env(safe-area-inset-bottom)` in padding | | | | |
| 25.7 | `overscroll-behavior-y` prevents bounce | | | | |
| 25.8 | Canvas `toBlob()` for photo downscale | | | | |
| 25.9 | `URL.createObjectURL()` for image preview | | | | |
| 25.10 | Pointer events (pointerdown/up) for long-press | | | | |

---

## 26  Accessibility (Baseline)

| # | Check |
|---|-------|
| 26.1 | All interactive elements are `<button>` or `<a>` (keyboard focusable) |
| 26.2 | Color contrast: gold text on dark bg meets 4.5:1 (verify with DevTools) |
| 26.3 | Faint text (`.faint`) meets minimum 3:1 for large text |
| 26.4 | Focus visible on tab-navigated elements |
| 26.5 | Modals/sheets trap focus (keyboard users can't tab behind overlay) |
| 26.6 | Screen reader can navigate: headings, buttons labeled, images have alt |
| 26.7 | Reduced motion: no essential animations that can't be disabled |
| 26.8 | Text scales when browser font size increased |

---

## 27  Performance

| # | Check |
|---|-------|
| 27.1 | Total JS payload < 50KB (no framework, vanilla JS) |
| 27.2 | First Contentful Paint < 1.5s on 3G throttle |
| 27.3 | No memory leaks: navigate between screens 50x, check heap |
| 27.4 | Event listeners cleaned up (sheets/toasts removed from DOM) |
| 27.5 | `setTimeout` for typing indicator cleared when navigating away |
| 27.6 | No duplicate event listeners on repeated `wire()` calls |
| 27.7 | Lighthouse Performance score ≥ 90 |
| 27.8 | Lighthouse PWA score ≥ 90 |

---

## Pre-Launch Blockers (Must Fix Before Live)

| # | Item | Status |
|---|------|--------|
| P1 | Remove TEST — Rae profile + Mike Valasek override from iOS builds | |
| P2 | Deploy all 3 Workers (auth, matching, consumables) with `wrangler deploy` | |
| P3 | Fill in `config.js` with live Worker URLs | |
| P4 | Create Apple Services ID + configure redirect URI | |
| P5 | Set `WEB_CLIENT_ID` on auth Worker | |
| P6 | Configure Stripe products matching pack/pass IDs | |
| P7 | Set `CHECKOUT_SUCCESS_URL` + `CHECKOUT_CANCEL_URL` in config.js | |
| P8 | Generate VAPID keys, set in config.js + Worker | |
| P9 | Deploy to Cloudflare Pages (or similar static host) with HTTPS | |
| P10 | Smoke test SIWA → Floor → Bid → Match → Chat → Reserve → Store on live | |
| P11 | Verify Stripe webhook fires and updates KV (Gavels balance, Pass status) | |
| P12 | Confirm server field shapes match `mapLot`, `syncMatches`, `syncIncoming` mappers | |
