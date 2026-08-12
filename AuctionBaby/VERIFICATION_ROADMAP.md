# Face Verification Roadmap — Real "Get Verified" Flow

## Current State (as shipped)

**What exists:**
- `VerificationSheet.swift` — UI with face icon, scan animation, success state
- `VerificationService.swift` — calls `POST /verify/start` on the auth Worker
- `auth/src/index.ts` — `handleVerifyStart()` returns `manual` (wait), `stub` (auto-pass), or `sdk` (Persona/Onfido placeholder)
- `NSCameraUsageDescription` already in Info.plist ✅
- User profile has `photoData: Data?` (primary photo) + `photoGallery: [Data]` — the reference images to match against
- `ROADMAP_V11.md` already names this as P1: "Liveness verification (Face-matched selfie)" using `VNDetectFaceLandmarksRequest` with a blink-challenge step

**What's fake:**
- Local/demo path: 1.7s fake scan animation → instant blue check. No camera, no face detection.
- Server path: Worker marks user "pending" → founder manually approves via admin endpoint. No face data is captured or compared.
- No camera is ever opened. No Vision framework is used. No face-to-photo matching occurs.

## Recommended Path: Apple Vision (On-Device, No Vendor Cost)

**Why not Persona/Onfido:**
- $1.50–$3 per verification — expensive at scale
- Third-party SDK adds dependency weight + privacy review complexity
- Sends user face data to a third-party server (privacy concern for a dating app)
- Apple reviewers may flag third-party biometric data collection

**Why Apple Vision:**
- Free — no per-check cost
- On-device — face data never leaves the phone
- No third-party SDK needed
- `NSCameraUsageDescription` already in Info.plist
- Vision framework is built into iOS, no dependencies
- App Store reviewers are familiar with it

## Build Plan — 4 Phases

### Phase 1: Camera Capture + Face Detection (2–3 days)
**Goal:** Open the front camera, detect a face in real-time, capture a selfie.

**Files to create:**
- `Features/Verification/CameraCaptureView.swift` — `UIViewRepresentable` wrapping `AVCaptureSession` with front camera
- `Features/Verification/FaceDetectionOverlay.swift` — real-time face bounding box overlay using `VNImageRequestHandler`

**Files to modify:**
- `Features/Profile/VerificationSheet.swift` — replace `startLocalScan()` with camera presentation

**Key APIs:**
- `AVCaptureSession` + `AVCaptureDeviceInput(.builtInWideAngleCamera, .front)`
- `VNDetectFaceRectanglesRequest` — real-time face detection on camera frames
- `VNImageRequestHandler` — feed camera sample buffers to Vision

**Acceptance criteria:**
- Camera opens with front camera
- Face bounding box overlay tracks the user's face in real-time
- "No face detected" state if face leaves frame
- Capture button or auto-capture when face is centered + stable

### Phase 2: Liveness Check — Blink Challenge (1–2 days)
**Goal:** Prove the camera input is a live person, not a photo/video.

**Files to create:**
- `Features/Verification/LivenessChecker.swift` — orchestrates the blink challenge

**Key APIs:**
- `VNDetectFaceLandmarksRequest` — gets eye landmarks
- Track eye openness over time (compare left/right eye landmark distances)
- Detect a blink event (eyes open → closed → open within 2s window)
- Require 1 blink to pass liveness

**Challenge flow:**
1. UI says "Blink once to verify you're real"
2. Camera frames feed into landmark detection
3. Detect blink pattern → pass
4. Timeout after 10s → fail + retry

**Acceptance criteria:**
- Blink detection works reliably (test with glasses, varying lighting)
- Photo held to camera fails (no blink detected)
- Video replay fails (blink timing doesn't match natural pattern)
- 10s timeout with retry option

### Phase 3: Face-to-Photo Matching (2–3 days)
**Goal:** Compare the live selfie to the user's profile photo(s).

**Files to create:**
- `Features/Verification/FaceMatcher.swift` — on-device face comparison

**Key APIs:**
- `VNDetectFaceCaptureQualityRequest` — pick the best capture frame
- `VNFaceObservation` — extract face landmarks from selfie
- Compare face landmarks (eye distance, nose position, mouth shape) between selfie and profile photo
- Vision doesn't have a direct "face match" API — use landmark distance comparison:
  - Extract 76-point landmarks from both faces
  - Normalize to unit distance between eyes
  - Compute Euclidean distance across landmark points
  - Threshold: distance < 0.15 = match (tunable)

**Alternative (simpler but less precise):**
- Use Core Image `CIFaceFeature` for both images
- Compare face bounding box proportions + facial feature positions
- Less accurate but simpler to implement

**Flow:**
1. After liveness passes, capture best-quality frame
2. Extract face landmarks from selfie
3. Load user's `photoData` (profile photo)
4. Extract face landmarks from profile photo
5. Compare landmarks → match/no-match
6. If profile has multiple photos, check against all — match against any one passes

**Acceptance criteria:**
- Same person: matches reliably (test across lighting, angles, glasses)
- Different person: fails
- No face in profile photo: graceful error ("Add a profile photo first")
- Multiple profile photos: checks all, matches best one

### Phase 4: Server Submission + Result (1–2 days)
**Goal:** Submit the verification result to the Worker for server-side truth.

**Files to modify:**
- `Services/VerificationService.swift` — add `submitVerificationResult()` 
- `auth/src/index.ts` — add `POST /verify/submit` endpoint

**New Worker endpoint:**
```
POST /verify/submit [auth]
Body: { selfieScore: Double, livenessPassed: Bool, faceMatchScore: Double }
→ { status: "passed" | "pending" | "failed" }
```

**Logic:**
- If `livenessPassed && faceMatchScore > threshold` → auto-pass (set `verified_at`, fire push)
- If below threshold → mark "pending" for manual review (founder can review the selfie vs profile)
- Store the scores (not the selfie image) on the user record

**Acceptance criteria:**
- Successful on-device verification → server marks user verified → blue check appears
- Failed face match → user can retry or gets "pending" for manual review
- Demo mode (no server) → local blue check only (current behavior)

## Total Estimate: 7–10 developer-days

## Architecture Summary

```
┌─────────────────────────────────────────────────┐
│ VerificationSheet (existing, modified)          │
│                                                  │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐ │
│  │  Camera   │→ │ Liveness │→ │ Face Match   │ │
│  │  Capture  │  │ (blink)  │  │ (vs profile) │ │
│  └───────────┘  └──────────┘  └──────────────┘ │
│       │              │              │           │
│  AVCaptureSession  VNFace        VNFace         │
│  + VNImage         Landmarks     Landmarks      │
│    Request           Request       + distance   │
│                                                  │
│  Result → VerificationService.submitResult()    │
│         → POST /verify/submit → Worker          │
│         → verified_at set → blue check live     │
└─────────────────────────────────────────────────┘
```

## Privacy Considerations

- **Selfie never leaves the device** — only the match score is sent to the server
- **Profile photo stays on device** — compared locally via Vision
- **No biometric data stored** — face landmarks are computed in memory and discarded
- `NSCameraUsageDescription` already in Info.plist: "Auction Baby uses the camera to verify your identity with a quick face match. Your photo is never stored or shared."
- No third-party receives any face data (unlike Persona/Onfido)

## App Store Review Notes

For the verification flow, include in review notes:
- "Verification uses Apple's Vision framework for on-device face detection and liveness checks"
- "No biometric data is transmitted or stored — only a boolean match result"
- "Camera is used only during the verification flow, with user consent"
- "Demo mode (name 'demo') simulates the flow without camera for reviewer convenience"

## Key File Locations

| File | Purpose |
|------|---------|
| `Features/Profile/VerificationSheet.swift` | Main UI — replace fake scan with real camera flow |
| `Services/VerificationService.swift` | Server communication — add submit endpoint |
| `auth/src/index.ts` | Worker — add `POST /verify/submit` |
| `Models/Profile.swift` | Has `photoData` + `photoGallery` — reference photos |
| `App/AuctionBabyApp.swift` | Wires `VerificationService` — no changes needed |
| `Info.plist` (via `project.yml`) | Has `NSCameraUsageDescription` ✅ |

## Dependencies

- **AVFoundation** — camera capture (already linked via StoreKitTest framework pattern)
- **Vision** — face detection, landmarks, capture quality (built into iOS, no package needed)
- **Core Image** — optional, for simpler face feature extraction fallback

No new Swift packages or CocoaPods required. Everything is in Apple's standard frameworks.