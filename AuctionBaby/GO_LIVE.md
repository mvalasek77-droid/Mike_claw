# Auction Baby — Go-Live Runbook

The code is done and the branch builds on iOS 26.1. Everything below is ops,
Xcode, or testing. Do the phases in order; Phase 1 and Phase 2 are independent
and unblock everything else, so start there.

Legend: ☐ todo · ✅ done · ⛔ blocked

---

## Phase 1 — Configure the backend (~10 min, do first)

- ☐ **1. Set the 3 APNs secrets on the staging Auth Worker.**
  Get the `.p8` from **Apple Developer → Keys → + → Apple Push Notifications**
  (downloadable once — save it somewhere safe).
  ```bash
  cd AuctionBaby/auth
  wrangler secret put APNS_AUTH_KEY_P8 --env staging < ~/Downloads/AuthKey_XXXXXXXXXX.p8
  wrangler secret put APNS_KEY_ID  --env staging     # 10-char Key ID from Apple
  wrangler secret put APNS_TEAM_ID --env staging     # 10-char Team ID
  ```
- ☐ **2. Verify** — hit the staging Auth Worker's `/health`; confirm
  `apns.configured: true`.

---

## Phase 2 — Prepare the Xcode project (~10 min)

- ☐ **3. Create your real secrets file** (gitignored — never commit it).
  ```bash
  cd AuctionBaby/Config
  cp Secrets.xcconfig.example Secrets.xcconfig
  ```
  Fill in the **staging** Worker URLs: `AB_AUTH_URL`, `AB_MATCHING_URL`
  (and `AB_TERMS_URL` / `AB_PRIVACY_URL` if those pages are hosted).
- ☐ **4. Open the project.**
  ```bash
  open AuctionBaby/AuctionBaby.xcodeproj
  ```
- ☐ **5. Signing & Capabilities** (select the app target):
  - Set your **Team**
  - **+ Capability → Sign in with Apple**
  - **+ Capability → Push Notifications** ← generates the `.entitlements`
    file the OS needs to issue a device token
- ☐ **6. Build to confirm green** — ⌘B on an iOS 26 simulator.

---

## Phase 3 — Single-device smoke test (~15 min)

- ☐ **7. Run** (⌘R) on a simulator **signed into iCloud**
  (Settings → sign in with **Apple ID #1**).
- ☐ **8. Test Sign in with Apple** — complete SIWA → DOB → role → profile →
  reach the floor.
- ☐ **9. Walk single-device rows** in `QA_CHECKLIST.md` §2–§6 (browse, bid,
  my bids, profile edit, paywall). Log anything odd in `BUGS.md`.

---

## Phase 4 — Two-account cross-device test (the real validation)

- ☐ **10. Line up the second identity** — a second simulator signed into
  **Apple ID #2**, or (smoother) one simulator + one physical device. Both
  builds must point at the **same staging Workers**.
- ☐ **11. Assign roles** — Device A = man/bidder, Device B = woman/lot. Both
  complete onboarding so real profiles sync to D1.
- ☐ **12. Run `DUAL_DEVICE_TEST.md` refresh-first** — §1 discovery → §2 bid →
  §3 accept → §4 chat → §5 whisper-nod → §7 block. Pull-to-refresh to move
  state between devices (no push needed yet).

---

## Phase 5 — Push matrix (needs Phase 1 done)

- ☐ **13. Grab each device's APNs token** from the Xcode console
  (logged on registration).
- ☐ **14. Send each event** with the `simctl push` payloads in the
  `DUAL_DEVICE_TEST.md` appendix — verify `bid.received` → B,
  `bid.accepted` → A, `message.received` → deep-links into the chat, etc.
  Test both **foreground** (banner, no nav) and **background-tap** (deep-link).

---

## Phase 6 — Pre-submission (when the above is green)

- ☐ **15. Run the `⌘U` unit suite** — pre-boot the sim first to avoid the
  Simulator-service disconnect that shows "0 tests."
- ☐ **16. Finish `QA_CHECKLIST.md`** §10 (accessibility), §11 (performance),
  §12 (App Store readiness).
- ☐ **17. Rotate the old admin credential** in your Worker secrets (still
  outstanding from the earlier QA sweep).
- ☐ **18. Deploy Workers to production** (not staging), point a Release build's
  `Secrets.xcconfig` at them, archive → TestFlight.

---

## Critical path

```
APNs secrets ─┐
              ├─► fresh build ─► SIWA works ─► 2 accounts ─► dual-device pass ─► push pass ─► TestFlight
Xcode caps ───┘
```

**Hard dependency:** the dual-device and push phases need **two signed-in Apple
IDs** — sort that out early.

Anything the dual-device or push runs turn up is the only category left that
could need a code change — capture it in `BUGS.md`.
