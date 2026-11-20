# BoxCall build 6 — watch companion resubmit checklist

Hand this to Kimi (or follow it yourself). It assumes you are on the Xcode
machine with the repo already cloned.

---

## Part 1 — Pull the fix and reset the build

The "empty operand (in target 'BoxCallWatch')" error was caused by a
missing root `Contents.json` in the watch target's asset catalog. The fix
is committed as `38c0a0f8` on branch `claude/movie-betting-app-hspuu3`.
Xcode caches the broken dependency file in DerivedData, so pulling alone
is **not** enough — you must clear DerivedData too.

Run these in order, in the repo root:

```bash
# 1. Make sure nothing local is lost
git status

# 2. Get the fix
git fetch origin
git checkout claude/movie-betting-app-hspuu3
git pull --ff-only

# 3. Confirm the fix is actually there
ls BoxCall/BoxCallWatch/Assets.xcassets/Contents.json
cat BoxCall/BoxCallWatch/Assets.xcassets/Contents.json
#  → must print:  {"info":{"author":"xcode","version":1}}

# 4. Regenerate the Xcode project from project.yml
cd BoxCall
xcodegen generate
cd ..

# 5. Nuke the stale DerivedData for BoxCall
rm -rf ~/Library/Developer/Xcode/DerivedData/BoxCall-*

# 6. Nuke Xcode's module cache too (cheap, often unsticks things)
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
```

Then in Xcode:

1. **File → Close Project**, then reopen `BoxCall/BoxCall.xcodeproj`.
2. **Product → Clean Build Folder** (⇧⌘K).
3. Select the `BoxCall` scheme (not BoxCallWatch) and the
   **Any iOS Device (arm64)** destination.
4. **Product → Archive**.

The archive should now complete without the "empty operand" error.

---

## Part 2 — If the archive still fails

Work the list top to bottom. Stop at the first thing that reproduces or
fixes the error.

### 2a. Confirm the fix is really in the project

```bash
grep -r "Assets.xcassets/Contents.json" BoxCall/BoxCall.xcodeproj/
```

If that prints nothing for the watch target, `xcodegen` didn't pick it up.
Fix: delete `BoxCall/BoxCall.xcodeproj` entirely and re-run
`xcodegen generate` from `BoxCall/`.

### 2b. Confirm the app icon is big enough

watchOS 10 wants a single 1024×1024 PNG with alpha stripped:

```bash
file BoxCall/BoxCallWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# → PNG image data, 1024 x 1024, 8-bit/color RGB, non-interlaced
```

If it says anything else (RGBA, wrong size), export a fresh 1024×1024 RGB
PNG from the design asset and overwrite that file. The App Store will
reject an icon with an alpha channel.

### 2c. Confirm actool actually sees the catalog

Build and grep the full log:

```bash
xcodebuild -scheme BoxCall -destination 'generic/platform=watchOS' \
  -archivePath build/BoxCall.xcarchive clean archive 2>&1 \
  | tee /tmp/archive.log
grep -E "(actool|assetcatalog_dependencies|BoxCallWatch)" /tmp/archive.log
```

If you see `actool` running against the watch catalog and it still writes
an empty dependency file, the catalog has a second hidden problem (a
`.DS_Store`, a stray `.jpg` outside an imageset, a bad imageset). Clean
it with:

```bash
find BoxCall/BoxCallWatch/Assets.xcassets -name ".DS_Store" -delete
find BoxCall/BoxCallWatch/Assets.xcassets -maxdepth 1 -type f \
  ! -name "Contents.json" -ls
# anything printed here that is NOT Contents.json should be moved into
# an imageset or deleted
```

### 2d. Signing

If the error flips to a code signing failure for `BoxCallWatch`:

1. Target `BoxCallWatch` → Signing & Capabilities.
2. Team: your BoxCall team.
3. Bundle ID: `com.boxcall.app.watchkitapp` (must match `project.yml`).
4. Provisioning: **Automatically manage signing**, then let Xcode
   generate it. If it won't, go to developer.apple.com → Certificates &
   Identifiers → Identifiers → add `com.boxcall.app.watchkitapp` with
   App Groups capability on `group.com.boxcall.shared`.
5. Same thing for `BoxCallWatchComplication` with
   `com.boxcall.app.watchkitapp.boxcallcomplication`.

### 2e. Last resort — rebuild the appiconset

If the appiconset itself looks corrupted (Xcode shows the icon slot but
archive still fails to compile the catalog):

```bash
rm -rf BoxCall/BoxCallWatch/Assets.xcassets/AppIcon.appiconset
```

Then in Xcode: watch target → Assets.xcassets → right-click →
**New watchOS App Icon**, name it `AppIcon`, drop the 1024×1024 PNG in.
Commit and try the archive again.

---

## Part 3 — Upload to App Store Connect

Once archive succeeds:

1. Organizer opens automatically. Pick the archive you just made.
2. **Distribute App → App Store Connect → Upload**.
3. **Automatically manage signing** → Next → Upload.
4. Wait 5–20 minutes for Apple to finish processing on the backend.
5. In App Store Connect → BoxCall → the submission (1.0 build 6):
   - Attach the new build once it finishes processing.
   - Open **App Review → Resolution Center** for Guideline 2.1(a).
   - Paste the reply from
     `appstore/guideline_2_1_a_response.md`.
   - **Submit for Review**.

---

## Part 4 — About your Intel Mac + OCLP + Xcode 27.1

Honest read on what you found online:

- Yes, you can download the `Xcode_27.1.xip` from
  developer.apple.com/download (Apple ID login, no paid account needed)
  and expand it into `/Applications`. The Mac App Store refuses based on
  SMBIOS; the direct `.xip` doesn't.
- It **will** launch on OCLP-spoofed Tahoe on a Haswell-or-newer Intel
  Mac Pro. A 2015 Mac Pro (`MacPro6,1`) is Ivy Bridge-EP — that's the
  risky generation. Some units have AVX2, some don't; if it crashes on
  launch with an illegal instruction, that's why, and there's no
  software fix.
- The `Info.plist` SMBIOS check the article mentions is real: your OCLP
  config has to spoof one of the four supported models. For a 2015 Mac
  Pro the usable spoof is `MacPro7,1` (2019 Mac Pro) — not the iMac or
  MacBook Pro ones.
- Caveats that bite on submission day:
  - **The watchOS simulator will not run** on an Intel Mac under any
    spoof. It needs Apple Silicon. You can still **archive** the watch
    target against a device destination (which is all you need for the
    submission), but you can't test the watch app in a simulator.
  - **Apple Intelligence coding features** (predictive completion,
    on-device model) will not work. Fine — you don't need them.
  - **Notarization and upload to App Store Connect** work normally from
    an Intel Mac. That part doesn't care about the CPU.
  - **Xcode 27.1 on Tahoe** needs about 50 GB free during the `.xip`
    expand step. Clear space first.

If Xcode 27.1 crashes on your 2015 Mac Pro and won't launch at all, the
pragmatic alternatives, in order of least pain:

1. **Rent a Mac mini M-series by the hour** (MacStadium, MacInCloud,
   AWS EC2 Mac — about $0.70–$1.20/hr). Clone the repo, run the Part 1
   checklist, archive, upload. One hour is plenty.
2. **Build on GitHub Actions** using the `macos-15` runner, which has
   Xcode 16.x. You'd need to add an archive + upload workflow and
   App Store Connect API keys. More setup, but it runs on every push
   after that.
3. **Borrow an M-series Mac for 15 minutes** — literally all you need
   to do is open the project, archive, upload.

If you want, I can set up the GitHub Actions archive + upload workflow
on the `claude/movie-betting-app-hspuu3` branch next, so you have a
fallback that doesn't depend on which Mac you're on.
