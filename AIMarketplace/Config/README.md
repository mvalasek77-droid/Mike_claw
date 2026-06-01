# Build configuration

`Build.xcconfig` is the project's base build config. It defines empty
defaults for the production backend values and optionally pulls in
`Secrets.xcconfig` (gitignored) when it exists.

## What gets baked in

Two values:

| Build setting | Substituted into Info.plist key | Read by |
|---|---|---|
| `AIMKT_WORKER_URL` | `AIMKT_WORKER_URL` | `BackendConfig.workerURL` |
| `AIMKT_SHARED_SECRET` | `AIMKT_SHARED_SECRET` | `BackendConfig.sharedSecret` |

When both are filled in, every creator who installs the app gets a one-tap
Stripe-onboarding flow with no developer-mode UI visible — they never see a
Worker URL or a shared secret. When they're empty, the app falls back to
the admin Payout-Setup screen so you can paste values at runtime for dev.

## Setup (one-time, on each dev machine that builds for release)

```bash
cd AIMarketplace/Config
cp Secrets.xcconfig.example Secrets.xcconfig
# Edit Secrets.xcconfig — paste your real Worker URL + the shared secret
# you set with `wrangler secret put APP_SHARED_SECRET`.

cd ..
xcodegen generate    # picks up the configFiles binding
open AIMarketplace.xcodeproj
```

Build & run — done.

## Why a separate file

The Worker URL is fine to commit, but the `APP_SHARED_SECRET` lives in two
places: on the Worker (set via wrangler) and in the app (so requests can
authenticate). Anyone with both can call your Worker, so we keep the value
out of git the same way the wrangler secrets are kept out of git. The
`#include?` directive in Build.xcconfig means the build never breaks if
Secrets.xcconfig is missing — you just get an unbundled-Worker build that
admins can configure at runtime.

## Rotating the secret

If the shared secret ever leaks:

1. `npx wrangler secret put APP_SHARED_SECRET` — paste a fresh value
2. Update `Secrets.xcconfig` with the same fresh value
3. `xcodegen generate && archive` — ship a new build

Existing installs with the old secret will start getting 401s from the
Worker; they'll need the update.
