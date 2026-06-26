# Watchfighter — Path to a Sell-Worthy Release

Honest checklist to get this from "great build" to "on the App Store." Ordered by
what actually blocks a sale.

## ✅ Already in place (Codex base + FF layer)
- Working watchOS app: Tournament / VS / Learn, 16 fighters, near-impossible boss.
- Real **digitized-sprite characters**, **voice callouts** (FIGHT/COMBO/FINISH/
  KO/MILLION/TITAN), **music**.
- **App icon** set (Icon-*.png), **PrivacyInfo.xcprivacy** present.
- **FF storytelling** woven in (intro, midpoint, pre-boss, and the Pit on a loss).
- Best-score persistence; unlock progression.

## ⛔ Blocks release (must do, in order)
1. **Build + device pass.** `xcodegen generate` then build to a real Apple Watch.
   Play a full tournament run, every menu, both win/loss paths. Fix any compile
   or runtime issues. *(Nothing below matters until this is green.)*
2. **Content rating.** There's stylized blood/finishers — file the correct age
   rating in App Store Connect (cartoon/fantasy violence; blood). Get this right
   or review will reject.
3. **App Store Connect metadata:** name, subtitle, promo text, description,
   keywords, support URL, category (Games → Action/Arcade).
4. **Screenshots** for every required Apple Watch size (use the simulator: title,
   a fight, a VS card, a cutscene, the boss). This is the #1 thing that sells.
5. **Privacy nutrition label.** If the app collects nothing (offline), declare
   "No data collected" — verify the manifest matches.
6. **Versioning:** set `CFBundleShortVersionString` (1.0) and build number.
7. **Bundle ID + signing:** unique reverse-DNS bundle id, Apple Developer
   Program ($99/yr) for distribution, App Store provisioning.

## 🟡 Strongly recommended for "addictive / reviewable"
- **First-run feel:** make the very first fight winnable and readable; the Learn
  mode should be one tap from the title.
- **Daily hook:** a "best streak" / "fastest clear" stat on the title screen
  (you already persist bestScore — surface a streak too).
- **Accessibility:** VoiceOver labels on menu buttons; honor Reduce Motion for
  screen shake/finisher bursts.
- **Tutorial prompt** the first time the player enters Tournament.

## 📈 Post-1.0 (depth that keeps people coming back)
- The full **Hell demon-fight** loop (see `HELL_LOOP_PATCH.md`).
- **Per-character story routes** + unique endings (FF-style arcs).
- **Unlockable alt-palettes** for fighters (cheap, very 90s, high retention).
- Online leaderboard for fastest tournament clear.

## Reality check
The game is genuinely close to a fun, original, 90s-nostalgic watch fighter. The
gap to "sell-worthy" is now mostly **release engineering** (build, rating, store
assets), not more features. Do step 1, send me what breaks, and I'll drive the
rest.
