# GitHub Actions — BoxCall Release Setup

One-time setup for the `BoxCall iOS Release` workflow
(`.github/workflows/boxcall-ios-release.yml`). After this is done, every
App Store upload is a two-click operation that doesn't need a local Mac.

---

## What you'll end up with

A manual workflow in the GitHub Actions tab of your repo named
**BoxCall iOS Release**. Click **Run workflow**, pick the branch
(`claude/movie-betting-app-hspuu3`), click Run. 15–25 minutes later the
build is in App Store Connect ready to attach to a submission. Build
number auto-increments from the GitHub run number, so Apple never
rejects for "build already used".

---

## Part A — Create the App Store Connect API key (once)

1. Sign in to https://appstoreconnect.apple.com
2. **Users and Access → Integrations → App Store Connect API**.
3. Click **(+)** to generate a key.
4. Name: `GitHub Actions BoxCall`. Access: **App Manager** (minimum for
   upload).
5. Click Generate. Apple shows the key once:
   - Download `AuthKey_XXXXXXXXXX.p8` — **you cannot download it again**.
   - Copy the **Key ID** (10 chars, e.g. `ABC123DEF4`).
   - Copy the **Issuer ID** at the top of the page (a UUID).

Keep the `.p8` file somewhere safe (1Password or similar) — if you lose
it, you have to revoke and start over.

---

## Part B — Export your iOS Distribution certificate (once)

On any Mac that already has your signing cert (yours, Kimi's, a loaned
M-series — doesn't matter which, as long as it can sign builds):

1. Open **Keychain Access**.
2. In the sidebar pick **login** keychain → **My Certificates**.
3. Find the entry starting with **Apple Distribution: …** that matches
   the BoxCall team.
4. **Right-click → Export "Apple Distribution: …"**.
5. Save as `BoxCallDist.p12`. When prompted, set a password — write it
   down, you'll paste it into GitHub in a moment.
6. Convert to base64:

   ```bash
   base64 -i ~/Downloads/BoxCallDist.p12 | pbcopy
   ```

   The base64 blob is now in your clipboard.

---

## Part C — Add six repository secrets

GitHub: **Settings → Secrets and variables → Actions → New repository
secret**. Add each of these:

| Name | Value |
|---|---|
| `APPLE_DIST_CERT_P12` | Paste the base64 blob from Part B step 6. |
| `APPLE_DIST_CERT_PASSWORD` | The password you set on the `.p12` in Part B step 5. |
| `KEYCHAIN_PASSWORD` | Any long random string. Not reused anywhere — just locks the ephemeral runner keychain. Generate one with `openssl rand -hex 24`. |
| `APPSTORE_CONNECT_KEY_ID` | The 10-char Key ID from Part A step 5. |
| `APPSTORE_CONNECT_ISSUER_ID` | The UUID Issuer ID from Part A step 5. |
| `APPSTORE_CONNECT_PRIVATE_KEY` | The **entire contents** of the `AuthKey_XXXXXXXXXX.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines. Paste it as-is; GitHub preserves newlines. |

---

## Part D — Run it

1. GitHub repo → **Actions** tab → **BoxCall iOS Release** in the left
   sidebar → **Run workflow**.
2. Branch: `claude/movie-betting-app-hspuu3`.
3. Leave the build number suffix empty.
4. Click **Run workflow**.

Watch the job. Expect ~15–25 minutes on a `macos-15` runner. The last
step is the actual upload; when it succeeds App Store Connect takes
another 5–15 minutes to finish backend processing before the build
shows up ready to attach to your 1.0 submission.

If a step fails, the job uploads `archive.log` and `export.log` as an
artifact at the bottom of the run page — download those to diagnose.

---

## Part E — Attach the build and reply to Apple

Once the new build appears in App Store Connect under BoxCall → TestFlight
or the 1.0 submission page:

1. App Store Connect → BoxCall → the 1.0 submission (currently marked
   "Rejected" for 2.1(a)).
2. Build section → **(+)** → pick the build you just uploaded.
3. **App Review → Resolution Center → Reply**.
4. Paste the text from `appstore/guideline_2_1_a_response.md`.
5. **Submit for Review**.

---

## Troubleshooting

**"No signing certificate 'iOS Distribution' found"** during archive
→ the `.p12` import didn't actually land a signing identity. Re-export
from Keychain Access making sure you picked the My Certificates entry
(which includes the private key), not the Certificates entry (public
only).

**"error: exportArchive: No profiles for 'com.boxcall.app' were found"**
→ the API key doesn't have access to the app. In App Store Connect →
Users and Access → the API key → Access, give it App Manager on the
BoxCall app (or the whole team).

**"ITMS-90022: Missing required icon file"** at upload
→ the watch app icon isn't a clean 1024×1024 RGB PNG. Replace
`BoxCall/BoxCallWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
with one that is, commit, push, run the workflow again.

**Archive step fails with the old watch asset-catalog "empty operand"**
→ shouldn't happen on CI because CI has no DerivedData cache, but if it
does, confirm `BoxCall/BoxCallWatch/Assets.xcassets/Contents.json` is
checked in with `git show HEAD -- BoxCall/BoxCallWatch/Assets.xcassets/Contents.json`.
