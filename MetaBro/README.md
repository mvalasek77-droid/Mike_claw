# MetaBro — iOS App

A premium social network for men that fuses **Facebook**'s social graph with
**Reddit**'s interest graph. Built native in **SwiftUI** for **iOS 26** with a
**Liquid Glass** design system.

> Product spec and full build prompt: [`../metabro_prompt.md`](../metabro_prompt.md)

## Status — Phase 0 + Phase 1 (the core loop)

The senior-engineer foundation plus the end-to-end Reddit/Facebook core loop:
**discover communities → open a post → read & vote on a threaded discussion →
reply.**

- ✅ **Liquid Glass design system** — tokens (color/spacing/radius/type/motion),
  glass surface modifier with Reduce-Transparency fallback, adaptive Core Haptics,
  springy vote control.
- ✅ **Architecture** — MVVM with `@Observable`, protocol-based services,
  dependency injection container, type-safe routing, Swift 6 strict concurrency.
- ✅ **Networking** — `async/await` API client with exponential-backoff retry and
  typed `APIError`.
- ✅ **Auth & onboarding** — a launch gate restores a persisted identity or runs a
  three-step flow (welcome → claim a handle + display name → required Code of
  Conduct agreement) before the rest of the app is built, so mock seed data and
  "you are the author" checks always agree on who's signed in. `Session` is a
  thread-safe (`Mutex`-backed), injectable singleton; `AuthService` has mock and
  live implementations and never touches `Session` itself, keeping it race-free
  under Swift Testing's parallel suites.
- ✅ **Unified feed** — social + Bro-hood fusion, sort (Hot/New/Top),
  pull-to-refresh, tap-to-open, and full loading / empty / error / offline states.
- ✅ **Hybrid interactions** — Bro-hood (community) posts use **Reddit voting**;
  social posts use **Facebook-style reactions** (Respect/Strong/LOL/Like/Sad/
  Angry) with quick-tap, long-press picker, and a reaction summary. Both are
  optimistic with rollback.
- ✅ **Stories** — a Facebook-style rail at the top of the feed with seen/unseen
  rings and a full-screen viewer (segmented progress, 5s auto-advance, tap
  zones, Reduce-Motion aware).
- ✅ **Awards** — Reddit-style awards (Champ/Solid/Big Brain) you can give from
  any post, shown as badges; optimistic with rollback.
- ✅ **Threaded comments (post detail)** — Reddit-style nested tree with
  collapse/expand, OP highlight, per-comment optimistic voting, and an inline
  reply composer. Tree-flattening is pure & unit-tested; the list is virtualized.
- ✅ **Bro-hoods (communities)** — discover + optimistic join/leave with rollback.
- ✅ **Post composer** — create a post to a Bro-hood or your own feed (target
  picker, optional title, validation, success state); appears live in the shared
  feed.
- ✅ **Search** — debounced, case-insensitive search across communities + posts,
  hosted in the Bro-hoods tab via `.searchable`, tappable through to threads.
- ✅ **Profile** — identity header, Bro Cred (post + comment karma) breakdown,
  your joined Bro-hoods, and your authored posts (reflects new posts instantly).
- ✅ **Messaging (DMs)** — 1:1 and group threads, optimistic send with
  sending/sent/delivered/read receipts, a typing indicator, simulated replies,
  unread badges, and auto-scroll. All five tabs are now live.
- ✅ **Live backend path** — every service has a `Live*` implementation over an
  `async/await` API client (bodies + retries + typed errors), a documented
  endpoint map (`API`), a `PostDTO` mapping layer, and a `BackendConfig` feature
  flag. The app uses the live backend when one is configured, mocks otherwise —
  so it always launches and is fully interactive offline.
- ✅ **Tests** — Swift Testing units for the feed loop, comment tree + detail VM,
  communities VM, composer, profile, search, messaging, stories, awards,
  reactions, the live backend (DTO mapping, routes, config), and design-system logic.
- ✅ **Accessibility** — Dynamic Type, VoiceOver labels/values/hints, Reduce Motion
  and Reduce Transparency fallbacks, honest non-blank placeholders.

## Project layout

```
MetaBro/
├── App/                 App entry + root tab shell
├── Core/
│   ├── DesignSystem/    Tokens, LiquidGlass, Haptics, Components/
│   ├── DI/              AppContainer (dependency injection)
│   └── Networking/      APIClient, Endpoint, APIError
├── Models/              Codable domain models (no UI imports)
├── Services/            Protocols + Mock impls (Feed/Comment/Community/Profile/
│   └── Live/            Search/Messaging/Story); Live/ = backend-backed + DTOs
├── Features/
│   ├── Feed/            Unified feed: View + ViewModel + PostCard
│   ├── PostDetail/      Threaded comments + reply composer
│   ├── Communities/     Discover + join/leave Bro-hoods (+ search)
│   ├── Composer/        Create a post to a Bro-hood or your feed
│   ├── Search/          Debounced community + post search
│   ├── Messages/        DM list + chat thread (receipts, typing)
│   ├── Stories/         Story rail + full-screen viewer
│   └── Profile/         Identity + Bro Cred + your posts
└── Navigation/          Type-safe AppRoute / AppTab
MetaBroTests/            Swift Testing unit tests
```

## Build

The Xcode project is generated with [XcodeGen](https://github.com/yonyz/XcodeGen)
(same as the other apps in this repo):

```bash
cd MetaBro
xcodegen generate
open MetaBro.xcodeproj
```

Then build/run the `MetaBro` scheme, or run tests with ⌘U.

## Backend configuration

The app runs on in-memory mocks by default, so it launches and is fully
interactive with **no backend required**. To point at a real API, set these in
`Config/Build.xcconfig` (or a gitignored `Config/Secrets.xcconfig`):

```
METABRO_USE_LIVE = YES
METABRO_API_BASE_URL = https://api.metabro.app/v1
```

`BackendConfig` reads them at runtime; `AppContainer.resolve` then wires the
`Live*` services (over `LiveAPIClient`) instead of the mocks. The expected REST
contract is documented in `Core/Networking/APIEndpoints.swift`.

## Next phases

See the roadmap in [`../metabro_prompt.md`](../metabro_prompt.md): friends graph,
events & marketplace, moderation tools, notifications, then polish & scale.
