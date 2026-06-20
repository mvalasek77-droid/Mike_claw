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
- ✅ **Unified feed** — social + Bro-hood fusion, sort (Hot/New/Top),
  pull-to-refresh, tap-to-open, and full loading / empty / error / offline states.
- ✅ **Hybrid interactions** — Bro-hood (community) posts use **Reddit voting**;
  social posts use **Facebook-style reactions** (Respect/Strong/LOL/Like/Sad/
  Angry) with quick-tap, long-press picker, and a reaction summary. Both are
  optimistic with rollback.
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
- ✅ **Tests** — Swift Testing units for the feed loop, comment tree + detail VM,
  communities VM, composer, profile, search, and design-system logic.
- ✅ **Accessibility** — Dynamic Type, VoiceOver labels/values/hints, Reduce Motion
  and Reduce Transparency fallbacks, honest non-blank placeholders for unbuilt tabs.

## Project layout

```
MetaBro/
├── App/                 App entry + root tab shell
├── Core/
│   ├── DesignSystem/    Tokens, LiquidGlass, Haptics, Components/
│   ├── DI/              AppContainer (dependency injection)
│   └── Networking/      APIClient, Endpoint, APIError
├── Models/              Codable domain models (no UI imports)
├── Services/            Feed / Comment / Community / Profile / Search protocols + Mocks
├── Features/
│   ├── Feed/            Unified feed: View + ViewModel + PostCard
│   ├── PostDetail/      Threaded comments + reply composer
│   ├── Communities/     Discover + join/leave Bro-hoods (+ search)
│   ├── Composer/        Create a post to a Bro-hood or your feed
│   ├── Search/          Debounced community + post search
│   ├── Messages/        DM list + chat thread (receipts, typing)
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

The app runs entirely against `MockFeedService` today, so it launches and is
fully interactive with **no backend required**. Swap in a `LiveAPIClient`-backed
service in `AppContainer.live()` once the API is reachable.

## Next phases

See the roadmap in [`../metabro_prompt.md`](../metabro_prompt.md): social graph
(friends/reactions/stories), messaging, community depth (karma/awards/mod tools),
events/marketplace, then polish & scale.
