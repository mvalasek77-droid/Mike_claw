# MetaBro — iOS App

A premium social network for men that fuses **Facebook**'s social graph with
**Reddit**'s interest graph. Built native in **SwiftUI** for **iOS 26** with a
**Liquid Glass** design system.

> Product spec and full build prompt: [`../metabro_prompt.md`](../metabro_prompt.md)

## Status — Phase 0 + Phase 1 (the loop) foundation

This scaffold establishes the senior-engineer foundation and a working,
end-to-end **unified feed** slice:

- ✅ **Liquid Glass design system** — tokens (color/spacing/radius/type/motion),
  glass surface modifier with Reduce-Transparency fallback, adaptive Core Haptics,
  springy vote control.
- ✅ **Architecture** — MVVM with `@Observable`, protocol-based services,
  dependency injection container, type-safe routing, Swift 6 strict concurrency.
- ✅ **Networking** — `async/await` API client with exponential-backoff retry and
  typed `APIError`.
- ✅ **Unified feed** — social + Bro-hood fusion, sort (Hot/New/Top),
  pull-to-refresh, optimistic voting with rollback, and full
  loading / empty / error / offline states.
- ✅ **Tests** — Swift Testing unit tests for the feed loop (load, empty, error,
  optimistic vote, rollback) and design-system logic (score formatting, vote math).
- ✅ **Accessibility** — Dynamic Type, VoiceOver labels/values, Reduce Motion and
  Reduce Transparency fallbacks, honest non-blank placeholders for unbuilt tabs.

## Project layout

```
MetaBro/
├── App/                 App entry + root tab shell
├── Core/
│   ├── DesignSystem/    Tokens, LiquidGlass, Haptics, Components/
│   ├── DI/              AppContainer (dependency injection)
│   └── Networking/      APIClient, Endpoint, APIError
├── Models/              Codable domain models (no UI imports)
├── Services/            FeedService protocol + MockFeedService
├── Features/Feed/       View + ViewModel + PostCard (the working slice)
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
