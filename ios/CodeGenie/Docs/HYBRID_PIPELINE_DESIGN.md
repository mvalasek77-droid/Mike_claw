# Hybrid AI-Steered Pipeline Design

> **Status:** Design Document  
> **Date:** 2026-06-09  
> **Authors:** CodeGenie Team  

---

## 1. Problem Statement

The current 10-step CodeGenie pipeline is **deterministic but brittle**. When a step encounters an ASC (App Store Connect) or Xcode failure, the entire pipeline halts and the user must manually diagnose and retry. The failure modes we encounter in practice are:

| # | Failure Mode | Current Behavior | User Impact |
|---|---|---|---|
| 1 | ASC 403 on app creation | `ascSignIn` returns `needs_sign_in`; user must open Safari | Pipeline stalls, user confused |
| 2 | Provisioning profile not found | `xcodebuild archive` fails with profile error | Cryptic Xcode error, manual fix needed |
| 3 | App icon alpha channel rejection | ASC rejects the IPA during upload | Upload fails, no clear remediation |
| 4 | Keychain access prompt | `xcodebuild` hangs on Keychain unlock dialog | Build appears stuck forever |
| 5 | Distribution cert missing | Archive/export fails with cert error | User must open Xcode manually |
| 6 | Build number conflict | Upload rejected — build number already exists | No auto-bump, must edit manually |

Each of these is **diagnosable** and **recoverable** by an AI agent that understands the error context and can take corrective action — but the current pipeline has no mechanism for this.

---

## 2. Core Concept: AI Steering

```
┌─────────────────────────────────────────────────────────┐
│                   Pipeline Executor                      │
│                                                          │
│  Step → Run ──→ Success ──→ Next Step                    │
│         │                                                 │
│         └──→ Failure ──→ AI Recovery Engine              │
│                              │                            │
│                              ├── Diagnose error           │
│                              ├── Propose recovery action   │
│                              └── Present to user           │
│                                    │                      │
│                              ┌─────┴──────┐               │
│                              │ RecoveryGate│               │
│                              │  (SwiftUI)  │               │
│                              └─────┬──────┘               │
│                    Approve │  Modify │  Reject              │
│                        ┌───┘        │      │              │
│                        ▼            ▼      ▼              │
│                  Apply fix     Edit params  Abort          │
│                        │                                     │
│                        └──→ Retry step ──→ ...              │
└─────────────────────────────────────────────────────────┘
```

**Key principles:**

1. **Pipeline steps run deterministically when they can.** No AI in the happy path.
2. **When a step fails, an AI steering agent diagnoses the error and proposes a recovery action.** The AI is not in the critical path — it's a fallback.
3. **Human gates remain for metadata review and Apple terms acceptance.** These are Apple-mandated human actions.
4. **A new "AI Recovery Gate" presents the diagnosis and proposed fix to the user.** The user can approve, modify, or reject. No autonomous recovery without human approval.

---

## 3. Step Classification

### 3.1 Step Types

Each pipeline step is classified into one of three types:

| Step | Type | Rationale |
|---|---|---|
| `perfection` | **Automated** | AI audit — no human needed |
| `metadata` | **AI-Steered** | AI generation; can fail on API errors |
| `reviewMetadata` | **Human Gate** | Apple-mandated review |
| `legalPages` | **Automated** | Generated & published automatically |
| `ascSignIn` | **AI-Steered** | 403s are common; AI can diagnose |
| `acceptAppleTerms` | **Human Gate** | Apple-mandated acceptance |
| `screenshots` | **Automated** | Simulator automation — no human needed |
| `archive` | **AI-Steered** | Xcode failures are recoverable |
| `upload` | **AI-Steered** | ASC API errors are diagnosable |
| `submit` | **AI-Steered** | ASC API errors are diagnosable |

### 3.2 Updated PipelineStep Enum (iOS)

```swift
// PipelineStepModels.swift — additions

extension PipelineStep {
    /// Whether this step can be auto-recovered by AI steering on failure.
    var isAISteered: Bool {
        switch self {
        case .metadata, .ascSignIn, .archive, .upload, .submit:
            return true
        default:
            return false
        }
    }

    /// Whether this step is fully automated (no human interaction needed).
    var isAutomated: Bool {
        switch self {
        case .perfection, .legalPages, .screenshots:
            return true
        default:
            return false
        }
    }
}
```

---

## 4. AI Steering Flow

### 4.1 Sequence Diagram

```
User        iOS Pipeline      Server          AI Engine
 │              │                 │                │
 │──Run Step───▶│                 │                │
 │              │──POST /step───▶│                │
 │              │                 │──Execute──────▶│
 │              │                 │                │
 │              │◀─200 OK────────│                │  (success)
 │◀─Step Done───│                 │                │
 │              │                 │                │
 │              │                 │                │  ── OR ──
 │              │                 │                │
 │              │◀─500 / Error───│                │  (failure)
 │              │                 │                │
 │              │──POST /steer──▶│                │
 │              │  {error ctx}   │──Diagnose─────▶│
 │              │                 │◀─Proposal──────│
 │              │◀─RecoveryProposal────────────────│
 │              │                 │                │
 │◀─RecoveryGate│                │                │
 │   Sheet──────│                │                │
 │              │                 │                │
 │──Approve────▶│                 │                │
 │              │──POST /recover─▶│                │
 │              │  {fix params}  │──Apply Fix────▶│
 │              │                 │──Retry Step───▶│
 │              │◀─200 OK────────│                │
 │◀─Step Done───│                 │                │
```

### 4.2 Failure → Recovery Lifecycle

1. **Step fails** → error captured in `PipelineStepStatus.failed(reason)`.
2. **AI Recovery Engine activated**: iOS client sends error context to `/api/build/:job_id/steer`.
3. **AI proposes recovery**: returns a `RecoveryProposal` with action type, description, and fix parameters.
4. **RecoveryGate sheet shown**: SwiftUI modal presents what failed, what AI suggests, and approve/modify/reject buttons.
5. **If approved**: iOS client calls `/api/build/:job_id/recover` with the approved recovery action. Server applies the fix and retries the step.
6. **If modified**: User edits the fix params (e.g., changing a build number), then submits.
7. **If rejected**: Pipeline halts. User can retry manually or cancel.

---

## 5. Data Model

### 5.1 New Swift Types (iOS)

```swift
// RecoveryProposal.swift — new file

/// The type of recovery action the AI proposes.
enum RecoveryAction: String, Codable, CaseIterable {
    /// Retry the step after applying a fix (e.g., bump build number).
    case retryWithFix
    /// The step requires manual human action (e.g., sign into ASC in Safari).
    case manualIntervention
    /// Skip this step — it's not critical for the pipeline to continue.
    case skip
    /// Abort the pipeline — the error is unrecoverable.
    case abort
}

/// A specific, diagnosed failure mode that the AI has identified.
enum FailureMode: String, Codable {
    case ascSignInRequired       // 403 on app creation / ASC API access
    case provisioningProfileNotFound
    case appIconAlphaChannel
    case keychainAccessPrompt
    case distributionCertMissing
    case buildNumberConflict
    case ascApiForbidden
    case ascApiError
    case archiveFailure
    case exportFailure
    case uploadFailure
    case unknown
}

/// Structured error context sent to the AI steering endpoint.
struct ErrorContext: Codable {
    let jobID: String
    let step: String          // "ascSignIn", "archive", etc.
    let failureMode: FailureMode
    let errorMessage: String  // Raw error message
    let httpStatusCode: Int?  // If from an API call
    let retryCount: Int       // How many times this step has been retried
    let previousErrors: [String] // Error messages from previous retries
}

/// A recovery proposal returned by the AI steering engine.
struct RecoveryProposal: Codable, Identifiable {
    let id: String            // UUID
    let jobID: String
    let step: String
    let failureMode: FailureMode
    let action: RecoveryAction
    let diagnosis: String     // Human-readable explanation of what went wrong
    let fixDescription: String // What the fix will do
    let fixParams: [String: String] // Parameters for the fix (e.g., new build number)
    let confidence: Double    // 0.0–1.0 — how confident the AI is in this fix
    let requiresHumanAction: Bool // Whether the user must do something outside the app
    let humanActionDescription: String? // e.g., "Sign into ASC at appstoreconnect.apple.com"
}

/// Request body for the recover endpoint.
struct RecoveryRequest: Codable {
    let jobID: String
    let step: String
    let proposalID: String
    let action: RecoveryAction
    let fixParams: [String: String] // May differ from proposal if user modified
}

/// Response from the recover endpoint.
struct RecoveryResult: Codable {
    let ok: Bool
    let stepRetrying: String?
    let message: String
}
```

### 5.2 Updated PipelineStepStatus (iOS)

```swift
// PipelineStepModels.swift — updated

enum PipelineStepStatus: Equatable {
    case pending
    case running
    case complete
    case failed(String)
    case recovering(RecoveryProposal)  // NEW: AI is proposing a fix

    var isPending: Bool  { self == .pending }
    var isRunning: Bool  { if case .running = self { return true } else { return false } }
    var isComplete: Bool { self == .complete }
    var isFailed: Bool   { if case .failed = self { return true } else { return false } }
    var isRecovering: Bool { if case .recovering = self { return true } else { return false } }
}
```

### 5.3 Updated PipelineRun (iOS)

```swift
// PipelineStepModels.swift — additions to PipelineRun

@MainActor
final class PipelineRun: ObservableObject {
    // ... existing properties ...

    /// The current AI recovery proposal, if a step has failed and AI has diagnosed it.
    @Published var aiRecoveryProposal: RecoveryProposal?

    /// Retry history for each step (to detect infinite loops).
    @Published var retryCountByStep: [PipelineStep: Int] = [:]

    /// Maximum retries before giving up on auto-recovery.
    static let maxRetries = 3

    /// Mark a step as recovering (AI has proposed a fix, awaiting user approval).
    func markRecovering(_ step: PipelineStep, proposal: RecoveryProposal) {
        stepStatuses[step] = .recovering(proposal)
        aiRecoveryProposal = proposal
        isRunning = false  // Pause the pipeline until user decides
    }

    /// Apply an approved recovery and retry the step.
    func approveRecovery(for step: PipelineStep) {
        stepStatuses[step] = .pending
        aiRecoveryProposal = nil
        retryCountByStep[step, default: 0] += 1
        // Pipeline auto-advance will pick this up
    }

    /// Reject the recovery and halt the pipeline.
    func rejectRecovery(for step: PipelineStep) {
        // Keep the failed status, clear the proposal
        aiRecoveryProposal = nil
        // Don't reset stepStatuses — it stays .failed
    }

    /// Whether the step has exceeded maximum retries.
    func hasExceededMaxRetries(for step: PipelineStep) -> Bool {
        (retryCountByStep[step] ?? 0) >= Self.maxRetries
    }
}
```

---

## 6. Recovery Scenarios

### 6.1 ASC 403 on App Creation (Sign-In Required)

**Failure:** `ascSignIn` step returns HTTP 403 from the ASC API. The JWT-authenticated API key doesn't have permission, or the user hasn't accepted terms in ASC.

**AI Diagnosis:**
```
Diagnosis: The App Store Connect API returned a 403 Forbidden response.
This typically means either:
1. The user hasn't signed into App Store Connect via Safari to accept
   the latest Terms of Service, or
2. The API key (N8LHKCW7K8) lacks the necessary permissions.

Fix: Open App Store Connect in Safari so you can sign in and accept
any pending agreements. Once done, the pipeline will re-check.
```

**Recovery Action:** `manualIntervention`  
**Fix Params:** `{ "url": "https://appstoreconnect.apple.com" }`

**Server-side steer handler:**
```rust
// In the steer endpoint, pattern-match on 403 + ASC context
RecoveryProposal {
    id: uuid::Uuid::new_v4().to_string(),
    job_id: job_id.clone(),
    step: "ascSignIn".to_string(),
    failure_mode: FailureMode::AscSignInRequired,
    action: RecoveryAction::ManualIntervention,
    diagnosis: "ASC API returned 403 Forbidden. You need to sign into ...".to_string(),
    fix_description: "Open App Store Connect in Safari to accept terms.".to_string(),
    fix_params: HashMap::from([("url".to_string(), "https://appstoreconnect.apple.com".to_string())]),
    confidence: 0.95,
    requires_human_action: true,
    human_action_description: Some("Sign into App Store Connect at https://appstoreconnect.apple.com and accept any pending agreements.".to_string()),
}
```

**iOS-side handling:**
```swift
// In RecoveryGate.swift
case .manualIntervention:
    // Show the user what they need to do externally
    // Provide a "Open in Safari" button
    // After user confirms they've done it, retry the step
    if let url = URL(string: proposal.fixParams["url"] ?? "") {
        UIApplication.shared.open(url)
    }
```

---

### 6.2 Provisioning Profile Not Found

**Failure:** `xcodebuild archive` fails with `no profile matching ... was found`.

**AI Diagnosis:**
```
Diagnosis: Xcode cannot find a provisioning profile matching the bundle ID.
This usually means no profile has been created in the Apple Developer Portal
for this app's bundle identifier.

Fix: Create a provisioning profile via the ASC API and install it locally,
then retry the archive step.
```

**Recovery Action:** `retryWithFix`  
**Fix Params:** `{ "create_profile": "true", "bundle_id": "..." }`

**Server-side recovery (Rust):**
```rust
async fn recover_provisioning_profile(
    job: &mut BuildJob,
    fix_params: &HashMap<String, String>,
) -> Result<(), String> {
    // 1. Use ASC API to create a provisioning profile
    // 2. Download and install the profile
    // 3. The retry of the archive step will pick it up
    let bundle_id = fix_params.get("bundle_id")
        .ok_or("Missing bundle_id in fix params")?;

    // Call ASC API: POST /v1/profiles
    // Install profile to ~/Library/MobileDevice/Provisioning Profiles/
    // ...
}
```

---

### 6.3 App Icon Alpha Channel Rejection

**Failure:** Upload to ASC is rejected with error about app icon containing an alpha channel.

**AI Diagnosis:**
```
Diagnosis: App Store Connect rejected the app icon because it contains
an alpha channel. Apple requires all app icons to be flat PNGs without
transparency.

Fix: Strip the alpha channel from the app icon asset and re-archive.
```

**Recovery Action:** `retryWithFix`  
**Fix Params:** `{ "strip_alpha": "true", "icon_path": "..." }`

**Server-side recovery:**
```rust
async fn recover_icon_alpha(
    job: &mut BuildJob,
    fix_params: &HashMap<String, String>,
) -> Result<(), String> {
    let icon_path = fix_params.get("icon_path")
        .ok_or("Missing icon_path")?;

    // Use image crate to strip alpha channel from PNG
    // Re-save the icon without alpha
    // The retry of archive will pick up the corrected icon
}
```

---

### 6.4 Keychain Access Prompt

**Failure:** `xcodebuild` hangs waiting for Keychain unlock (codesign wants access to `login.keychain`).

**AI Diagnosis:**
```
Diagnosis: The archive step appears stuck — Xcode is waiting for Keychain
access to sign the binary. This happens when the distribution certificate's
private key is in a locked Keychain.

Fix: Unlock the Keychain via CompanionBridge and retry the archive step.
```

**Recovery Action:** `retryWithFix`  
**Fix Params:** `{ "unlock_keychain": "true" }`

**Server-side recovery:**
```rust
async fn recover_keychain(
    job: &mut BuildJob,
    fix_params: &HashMap<String, String>,
) -> Result<(), String> {
    // Send unlock command to CompanionBridge
    // security unlock-keychain -p <password> ~/Library/Keychains/login.keychain-db
    let output = tokio::process::Command::new("security")
        .arg("unlock-keychain")
        .arg("-p")
        .arg(&keychain_password) // Retrieved from secure storage
        .arg(home_dir.join("Library/Keychains/login.keychain-db"))
        .output()
        .await
        .map_err(|e| format!("Failed to unlock keychain: {e}"))?;

    if !output.status.success() {
        return Err("Keychain unlock failed — password may be incorrect".to_string());
    }
    Ok(())
}
```

---

### 6.5 Distribution Certificate Missing

**Failure:** Archive/export fails with `no certificate matching ... was found` or `distribution certificate not found`.

**AI Diagnosis:**
```
Diagnosis: The archive step failed because no distribution certificate was
found in your Keychain. This is required to sign the IPA for App Store
distribution.

Fix: Create a distribution certificate via the ASC API and install it
locally, then retry.
```

**Recovery Action:** `retryWithFix`  
**Fix Params:** `{ "create_cert": "true", "cert_type": "distribution" }`

---

### 6.6 Build Number Conflict

**Failure:** Upload rejected with error `The build number ... already exists` or ASC returns a duplicate build number error.

**AI Diagnosis:**
```
Diagnosis: The build number (CFBundleVersion) in your project conflicts
with a build already uploaded to App Store Connect. Apple requires each
upload to have a unique build number.

Fix: Bump the build number from 1 to 2 and retry the archive step.
```

**Recovery Action:** `retryWithFix`  
**Fix Params:** `{ "bump_build_number": "true", "new_build_number": "2" }`

**Server-side recovery:**
```rust
async fn recover_build_number(
    job: &mut BuildJob,
    fix_params: &HashMap<String, String>,
) -> Result<(), String> {
    let new_number = fix_params.get("new_build_number")
        .ok_or("Missing new_build_number")?;

    let project_path = Path::new(&job.project_path);
    // Find Info.plist or project.yml and update CFBundleVersion
    // Or for Swift Package Manager projects, update Package.swift
    // ...
    Ok(())
}
```

---

## 7. Server Changes (Rust)

### 7.1 New Types

```rust
// builder/mod.rs — new types

/// Failure mode diagnosed by the AI steering engine.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FailureMode {
    AscSignInRequired,
    ProvisioningProfileNotFound,
    AppIconAlphaChannel,
    KeychainAccessPrompt,
    DistributionCertMissing,
    BuildNumberConflict,
    AscApiForbidden,
    AscApiError,
    ArchiveFailure,
    ExportFailure,
    UploadFailure,
    Unknown,
}

/// Recovery action proposed by the AI.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RecoveryAction {
    RetryWithFix,
    ManualIntervention,
    Skip,
    Abort,
}

/// Structured error context sent to the AI steering endpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorContext {
    pub job_id: String,
    pub step: String,
    pub failure_mode: FailureMode,
    pub error_message: String,
    pub http_status_code: Option<u16>,
    pub retry_count: u32,
    pub previous_errors: Vec<String>,
}

/// Recovery proposal returned by the AI steering engine.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveryProposal {
    pub id: String,
    pub job_id: String,
    pub step: String,
    pub failure_mode: FailureMode,
    pub action: RecoveryAction,
    pub diagnosis: String,
    pub fix_description: String,
    pub fix_params: HashMap<String, String>,
    pub confidence: f64,
    pub requires_human_action: bool,
    pub human_action_description: Option<String>,
}

/// Request body for the recover endpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoverRequest {
    pub job_id: String,
    pub step: String,
    pub proposal_id: String,
    pub action: RecoveryAction,
    pub fix_params: HashMap<String, String>,
}

/// Response from the recover endpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoverResponse {
    pub ok: bool,
    pub step_retrying: Option<String>,
    pub message: String,
}
```

### 7.2 New Endpoints

```rust
// server.rs — new route registrations

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        // ... existing routes ...
        .route("/api/build/:job_id/steer", post(steer))       // NEW
        .route("/api/build/:job_id/recover", post(recover))   // NEW
        .layer(cors)
        .with_state(state)
}
```

#### `POST /api/build/:job_id/steer` — Diagnose error and propose recovery

```rust
/// `POST /api/build/:job_id/steer` — AI steering diagnosis.
///
/// Accepts error context from the iOS client, diagnoses the failure mode,
/// and returns a recovery proposal for the user to approve.
async fn steer(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(context): Json<ErrorContext>,
) -> Result<Json<RecoveryProposal>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    // ── Diagnose failure mode ──────────────────────────────────────
    let proposal = diagnose_failure(&context, &job_arc).await?;

    // Store the proposal so the recover endpoint can validate it
    {
        let mut jobs = state.jobs.lock().await;
        // We store proposals in a separate HashMap on AppState
        // (See Section 7.3 — AppState changes)
    }

    Ok(Json(proposal))
}

/// Pattern-match on the error context to produce a recovery proposal.
async fn diagnose_failure(
    context: &ErrorContext,
    job_arc: &Arc<Mutex<BuildJob>>,
) -> Result<RecoveryProposal, (StatusCode, String)> {
    let job = job_arc.lock().await;

    match context.failure_mode {
        FailureMode::AscSignInRequired => {
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: "ascSignIn".to_string(),
                failure_mode: FailureMode::AscSignInRequired,
                action: RecoveryAction::ManualIntervention,
                diagnosis: "The App Store Connect API returned a 403 Forbidden response. This typically means you need to sign into App Store Connect and accept pending agreements.".to_string(),
                fix_description: "Open App Store Connect in Safari to sign in and accept any pending agreements.".to_string(),
                fix_params: HashMap::from([
                    ("url".to_string(), "https://appstoreconnect.apple.com".to_string()),
                ]),
                confidence: 0.95,
                requires_human_action: true,
                human_action_description: Some("Sign into App Store Connect at https://appstoreconnect.apple.com and accept any pending agreements.".to_string()),
            })
        },
        FailureMode::ProvisioningProfileNotFound => {
            let bundle_id = derive_bundle_id(&job.request);
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: "archive".to_string(),
                failure_mode: FailureMode::ProvisioningProfileNotFound,
                action: RecoveryAction::RetryWithFix,
                diagnosis: "Xcode cannot find a provisioning profile for this bundle ID. A new profile needs to be created via the Apple Developer Portal.".to_string(),
                fix_description: format!("Create a new provisioning profile for {bundle_id} via the ASC API and install it locally."),
                fix_params: HashMap::from([
                    ("create_profile".to_string(), "true".to_string()),
                    ("bundle_id".to_string(), bundle_id),
                ]),
                confidence: 0.85,
                requires_human_action: false,
                human_action_description: None,
            })
        },
        FailureMode::BuildNumberConflict => {
            // Parse current build number from error message and propose bump
            let current = parse_build_number_from_error(&context.error_message)
                .unwrap_or(1);
            let new_number = current + context.retry_count + 1;
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: "archive".to_string(),
                failure_mode: FailureMode::BuildNumberConflict,
                action: RecoveryAction::RetryWithFix,
                diagnosis: format!("Build number {current} already exists in App Store Connect. Each upload must have a unique build number."),
                fix_description: format!("Bump the build number from {current} to {new_number} and re-archive."),
                fix_params: HashMap::from([
                    ("bump_build_number".to_string(), "true".to_string()),
                    ("new_build_number".to_string(), new_number.to_string()),
                ]),
                confidence: 0.99,
                requires_human_action: false,
                human_action_description: None,
            })
        },
        FailureMode::AppIconAlphaChannel => {
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: "upload".to_string(),
                failure_mode: FailureMode::AppIconAlphaChannel,
                action: RecoveryAction::RetryWithFix,
                diagnosis: "App Store Connect rejected the app icon because it contains an alpha channel. Apple requires flat PNGs without transparency.".to_string(),
                fix_description: "Strip the alpha channel from the app icon asset and re-archive.".to_string(),
                fix_params: HashMap::from([
                    ("strip_alpha".to_string(), "true".to_string()),
                ]),
                confidence: 0.97,
                requires_human_action: false,
                human_action_description: None,
            })
        },
        FailureMode::KeychainAccessPrompt => {
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: "archive".to_string(),
                failure_mode: FailureMode::KeychainAccessPrompt,
                action: RecoveryAction::RetryWithFix,
                diagnosis: "The archive step is stuck because Xcode is waiting for Keychain access to sign the binary.".to_string(),
                fix_description: "Unlock the Keychain and retry the archive step.".to_string(),
                fix_params: HashMap::from([
                    ("unlock_keychain".to_string(), "true".to_string()),
                ]),
                confidence: 0.80,
                requires_human_action: false,
                human_action_description: None,
            })
        },
        FailureMode::DistributionCertMissing => {
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: "archive".to_string(),
                failure_mode: FailureMode::DistributionCertMissing,
                action: RecoveryAction::RetryWithFix,
                diagnosis: "No distribution certificate was found in the Keychain. This is required to sign the IPA for App Store distribution.".to_string(),
                fix_description: "Create a distribution certificate via the ASC API and install it locally.".to_string(),
                fix_params: HashMap::from([
                    ("create_cert".to_string(), "true".to_string()),
                    ("cert_type".to_string(), "distribution".to_string()),
                ]),
                confidence: 0.75,
                requires_human_action: true,
                human_action_description: Some("A distribution certificate will be created via ASC API. You may need to approve the certificate request in the Apple Developer Portal.".to_string()),
            })
        },
        _ => {
            // Unknown failure — offer manual intervention
            Ok(RecoveryProposal {
                id: uuid::Uuid::new_v4().to_string(),
                job_id: context.job_id.clone(),
                step: context.step.clone(),
                failure_mode: FailureMode::Unknown,
                action: RecoveryAction::ManualIntervention,
                diagnosis: context.error_message.clone(),
                fix_description: "This error could not be automatically diagnosed. Please review the error message and try again.".to_string(),
                fix_params: HashMap::new(),
                confidence: 0.0,
                requires_human_action: true,
                human_action_description: None,
            })
        }
    }
}
```

#### `POST /api/build/:job_id/recover` — Apply a recovery action and retry

```rust
/// `POST /api/build/:job_id/recover` — Apply a recovery action.
///
/// Accepts a user-approved recovery request, applies the fix, and
/// re-triggers the relevant pipeline step.
async fn recover(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(request): Json<RecoverRequest>,
) -> Result<Json<RecoverResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    // ── Apply the fix based on failure mode ──────────────────────────
    match request.action {
        RecoveryAction::RetryWithFix => {
            apply_fix(&job_arc, &request).await?;
            // Re-trigger the appropriate pipeline step
            let step = request.step.clone();
            // The iOS client will call the appropriate endpoint again
            Ok(Json(RecoverResponse {
                ok: true,
                step_retrying: Some(step),
                message: "Fix applied. Retry the step.".to_string(),
            }))
        },
        RecoveryAction::ManualIntervention => {
            // No server-side action needed — the user will do something
            // externally and then retry the step
            Ok(Json(RecoverResponse {
                ok: true,
                step_retrying: Some(request.step.clone()),
                message: "Manual action required. Complete the action and retry.".to_string(),
            }))
        },
        RecoveryAction::Skip => {
            Ok(Json(RecoverResponse {
                ok: true,
                step_retrying: None,
                message: "Step skipped.".to_string(),
            }))
        },
        RecoveryAction::Abort => {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Failed;
            job.error = Some("Pipeline aborted by user after recovery rejection.".to_string());
            Ok(Json(RecoverResponse {
                ok: false,
                step_retrying: None,
                message: "Pipeline aborted.".to_string(),
            }))
        },
    }
}

/// Apply a fix based on the fix_params in the recovery request.
async fn apply_fix(
    job_arc: &Arc<Mutex<BuildJob>>,
    request: &RecoverRequest,
) -> Result<(), (StatusCode, String)> {
    let job = job_arc.lock().await;

    if let Some(val) = request.fix_params.get("bump_build_number") {
        if val == "true" {
            let new_number = request.fix_params.get("new_build_number")
                .ok_or((StatusCode::BAD_REQUEST, "Missing new_build_number".to_string()))?;
            bump_build_number(&job.project_path, new_number)?;
        }
    }

    if let Some(val) = request.fix_params.get("strip_alpha") {
        if val == "true" {
            strip_icon_alpha(&job.project_path)?;
        }
    }

    if let Some(val) = request.fix_params.get("unlock_keychain") {
        if val == "true" {
            unlock_keychain()?;
        }
    }

    if let Some(val) = request.fix_params.get("create_cert") {
        if val == "true" {
            create_distribution_cert(&job.request).await?;
        }
    }

    if let Some(val) = request.fix_params.get("create_profile") {
        if val == "true" {
            let bundle_id = request.fix_params.get("bundle_id")
                .ok_or((StatusCode::BAD_REQUEST, "Missing bundle_id".to_string()))?;
            create_provisioning_profile(bundle_id).await?;
        }
    }

    Ok(())
}
```

### 7.3 AppState Changes

```rust
// server.rs — updated AppState

pub struct AppState {
    /// job_id → Arc-wrapped build job
    jobs: Mutex<HashMap<String, Arc<Mutex<BuildJob>>>>,
    /// job_id → broadcast sender for SSE events
    event_senders: Mutex<HashMap<String, broadcast::Sender<BuildEvent>>>,
    /// job_id → pending recovery proposal (awaiting user approval)
    recovery_proposals: Mutex<HashMap<String, RecoveryProposal>>,  // NEW
}
```

### 7.4 Structured Error Responses

Currently, step handlers return `(StatusCode, String)` errors. For AI steering to work, we need **structured** error info. Update handlers to return typed error information:

```rust
/// Structured error info for pipeline steps.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepError {
    pub step: String,
    pub failure_mode: FailureMode,
    pub message: String,
    pub http_status_code: Option<u16>,
    pub raw_output: Option<String>,    // stderr / response body
    pub retry_count: u32,
}

impl StepError {
    /// Convert to ErrorContext for the steer endpoint.
    pub fn to_error_context(&self, job_id: &str, previous_errors: &[String]) -> ErrorContext {
        ErrorContext {
            job_id: job_id.to_string(),
            step: self.step.clone(),
            failure_mode: self.failure_mode.clone(),
            error_message: self.message.clone(),
            http_status_code: self.http_status_code,
            retry_count: self.retry_count,
            previous_errors: previous_errors.to_vec(),
        }
    }
}
```

---

## 8. iOS Changes

### 8.1 RecoveryGate.swift — New SwiftUI View

```swift
import SwiftUI

/// A sheet that presents an AI-proposed recovery action to the user.
/// Shows what went wrong, what the AI suggests, and lets the user
/// approve, modify, or reject the fix.
struct RecoveryGate: View {
    let proposal: RecoveryProposal
    let onApprove: (RecoveryProposal) -> Void
    let onModify: (RecoveryProposal, [String: String]) -> Void
    let onReject: () -> Void

    @State private var modifiedParams: [String: String]
    @State private var isModifying = false

    init(
        proposal: RecoveryProposal,
        onApprove: @escaping (RecoveryProposal) -> Void,
        onModify: @escaping (RecoveryProposal, [String: String]) -> Void,
        onReject: @escaping () -> Void
    ) {
        self.proposal = proposal
        self.onApprove = onApprove
        self.onModify = onModify
        self.onReject = onReject
        self._modifiedParams = State(initialValue: proposal.fixParams)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // ── Failure Icon ──
                Image(systemName: failureIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .padding(.top, 8)

                // ── Diagnosis ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("What Went Wrong", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(proposal.diagnosis)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // ── Proposed Fix ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI Suggestion", systemImage: "wand.and.stars")
                        .font(.headline)
                    Text(proposal.fixDescription)
                        .font(.subheadline)
                    if proposal.confidence > 0 {
                        HStack(spacing: 4) {
                            Text("Confidence:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(proposal.confidence * 100))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(confidenceColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // ── Human Action Required ──
                if proposal.requiresHumanAction,
                   let actionDesc = proposal.humanActionDescription {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Action Required", systemImage: "person.fill")
                            .font(.headline)
                        Text(actionDesc)
                            .font(.subheadline)
                        if let urlStr = proposal.fixParams["url"],
                           let url = URL(string: urlStr) {
                            Link("Open in Safari", destination: url)
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // ── Modify Fix Params (expandable) ──
                if !proposal.fixParams.isEmpty && proposal.action == .retryWithFix {
                    DisclosureGroup("Edit Fix Parameters", isExpanded: $isModifying) {
                        ForEach(Array(proposal.fixParams.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Value", text: Binding(
                                    get: { modifiedParams[key] ?? "" },
                                    set: { modifiedParams[key] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding()
                }

                Spacer()

                // ── Action Buttons ──
                VStack(spacing: 12) {
                    Button {
                        if isModifying {
                            onModify(proposal, modifiedParams)
                        } else {
                            onApprove(proposal)
                        }
                    } label: {
                        Label(
                            proposal.action == .manualIntervention
                                ? "I've Done This — Retry"
                                : "Approve & Apply Fix",
                            systemImage: proposal.action == .manualIntervention
                                ? "checkmark.circle"
                                : "wand.and.stars.inverse"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Cancel Pipeline", role: .destructive) {
                        onReject()
                    }
                    .controlSize(.large)
                }
            }
            .padding()
            .navigationTitle("Recovery Needed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Helpers

    private var failureIcon: String {
        switch proposal.failureMode {
        case .ascSignInRequired:       return "person.badge.keypad"
        case .provisioningProfileNotFound: return "person.crop.circle.badge.exclamationmark"
        case .appIconAlphaChannel:     return "photo.badge.exclamationmark"
        case .keychainAccessPrompt:    return "key.fill"
        case .distributionCertMissing: return "certnoph.fill"
        case .buildNumberConflict:    return "number.circle"
        default:                       return "exclamationmark.triangle"
        }
    }

    private var confidenceColor: Color {
        if proposal.confidence >= 0.9 { return .green }
        if proposal.confidence >= 0.7 { return .orange }
        return .red
    }
}
```

### 8.2 Updated PipelineClient — New Endpoints

```swift
// PipelineClient.swift — additions

// MARK: - AI Steering

/// Request the AI steering engine to diagnose a failed step and propose a fix.
func steerRecovery(jobID: String, errorContext: ErrorContext) async throws -> RecoveryProposal {
    lastError = nil
    let body: [String: Any] = [
        "job_id": errorContext.jobID,
        "step": errorContext.step,
        "failure_mode": errorContext.failureMode.rawValue,
        "error_message": errorContext.errorMessage,
        "http_status_code": errorContext.httpStatusCode ?? NSNull(),
        "retry_count": errorContext.retryCount,
        "previous_errors": errorContext.previousErrors,
    ]
    let r = try await postJSON("/api/build/\(jobID)/steer", body: body)
    return RecoveryProposal(
        id: (r["id"] as? String) ?? UUID().uuidString,
        jobID: (r["job_id"] as? String) ?? jobID,
        step: (r["step"] as? String) ?? "",
        failureMode: FailureMode(rawValue: (r["failure_mode"] as? String) ?? "unknown") ?? .unknown,
        action: RecoveryAction(rawValue: (r["action"] as? String) ?? "abort") ?? .abort,
        diagnosis: (r["diagnosis"] as? String) ?? "Unknown error",
        fixDescription: (r["fix_description"] as? String) ?? "",
        fixParams: (r["fix_params"] as? [String: String]) ?? [:],
        confidence: (r["confidence"] as? Double) ?? 0.0,
        requiresHumanAction: (r["requires_human_action"] as? Bool) ?? false,
        humanActionDescription: r["human_action_description"] as? String
    )
}

/// Apply a user-approved recovery action.
func recoverStep(jobID: String, request: RecoveryRequest) async throws -> RecoveryResult {
    lastError = nil
    let body: [String: Any] = [
        "job_id": request.jobID,
        "step": request.step,
        "proposal_id": request.proposalID,
        "action": request.action.rawValue,
        "fix_params": request.fixParams,
    ]
    let r = try await postJSON("/api/build/\(jobID)/recover", body: body)
    return RecoveryResult(
        ok: (r["ok"] as? Bool) ?? false,
        stepRetrying: r["step_retrying"] as? String,
        message: (r["message"] as? String) ?? ""
    )
}
```

### 8.3 BuildScreen Integration

```swift
// In BuildScreen or PipelineView — observe pipeline failures and present RecoveryGate

@State private var recoveryProposal: RecoveryProposal?

// In the pipeline step execution:
func runStep(_ step: PipelineStep) async {
    pipelineRun.markRunning(step)

    do {
        let result = try await executeStep(step)
        pipelineRun.markComplete(step)
        advanceToNextStep()
    } catch {
        // Check if step is AI-steerable and hasn't exceeded max retries
        if step.isAISteered && !pipelineRun.hasExceededMaxRetries(for: step) {
            let errorContext = ErrorContext(
                jobID: currentJobID,
                step: step.rawValue,
                failureMode: diagnoseFailureMode(step: step, error: error),
                errorMessage: error.localizedDescription,
                httpStatusCode: extractHTTPStatus(from: error),
                retryCount: pipelineRun.retryCountByStep[step] ?? 0,
                previousErrors: []
            )

            // Call the AI steering endpoint
            if let proposal = try? await pipelineClient.steerRecovery(
                jobID: currentJobID,
                errorContext: errorContext
            ) {
                pipelineRun.markRecovering(step, proposal: proposal)
                recoveryProposal = proposal  // Show RecoveryGate sheet
                return
            }
        }

        // Fallback: just mark as failed
        pipelineRun.markFailed(step, error: error.localizedDescription)
    }
}

// RecoveryGate sheet
.sheet(item: $recoveryProposal) { proposal in
    RecoveryGate(
        proposal: proposal,
        onApprove: { approvedProposal in
            recoveryProposal = nil
            Task {
                let request = RecoveryRequest(
                    jobID: approvedProposal.jobID,
                    step: approvedProposal.step,
                    proposalID: approvedProposal.id,
                    action: approvedProposal.action,
                    fixParams: approvedProposal.fixParams
                )
                let result = try await pipelineClient.recoverStep(
                    jobID: currentJobID,
                    request: request
                )
                if result.ok, let retrying = result.stepRetrying {
                    let step = PipelineStep(rawValue: retrying)!
                    pipelineRun.approveRecovery(for: step)
                    runStep(step)  // Retry the step
                }
            }
        },
        onModify: { originalProposal, modifiedParams in
            recoveryProposal = nil
            Task {
                var params = modifiedParams
                let request = RecoveryRequest(
                    jobID: originalProposal.jobID,
                    step: originalProposal.step,
                    proposalID: originalProposal.id,
                    action: originalProposal.action,
                    fixParams: params
                )
                let result = try await pipelineClient.recoverStep(
                    jobID: currentJobID,
                    request: request
                )
                if result.ok, let retrying = result.stepRetrying {
                    let step = PipelineStep(rawValue: retrying)!
                    pipelineRun.approveRecovery(for: step)
                    runStep(step)
                }
            }
        },
        onReject: {
            let step = PipelineStep(rawValue: proposal.step)!
            pipelineRun.rejectRecovery(for: step)
            recoveryProposal = nil
        }
    )
}
```

### 8.4 Failure Mode Diagnosis (iOS-side helper)

```swift
/// Parse an error to determine the failure mode, for sending to the steer endpoint.
func diagnoseFailureMode(step: PipelineStep, error: Error) -> FailureMode {
    let message = error.localizedDescription.lowercased()

    switch step {
    case .ascSignIn:
        if message.contains("403") || message.contains("forbidden") {
            return .ascSignInRequired
        }
        return .ascApiForbidden

    case .archive:
        if message.contains("provisioning profile") || message.contains("no profile matching") {
            return .provisioningProfileNotFound
        }
        if message.contains("keychain") || message.contains("user interaction is not allowed") {
            return .keychainAccessPrompt
        }
        if message.contains("certificate") || message.contains("distribution cert") {
            return .distributionCertMissing
        }
        if message.contains("alpha") && message.contains("icon") {
            return .appIconAlphaChannel
        }
        return .archiveFailure

    case .upload:
        if message.contains("build number") || message.contains("already exists") {
            return .buildNumberConflict
        }
        if message.contains("alpha") || message.contains("icon") {
            return .appIconAlphaChannel
        }
        return .uploadFailure

    default:
        return .unknown
    }
}
```

---

## 9. Flow Diagrams

### 9.1 Happy Path (No Failures)

```
perfection → metadata → reviewMetadata (HUMAN) → legalPages → ascSignIn
→ acceptAppleTerms (HUMAN) → screenshots → archive → upload → submit
```

### 9.2 Failure → AI Recovery Path

```
archive ──→ FAIL (provisioning profile not found)
         │
         ├── iOS: diagnoseFailureMode() → .provisioningProfileNotFound
         ├── iOS: POST /api/build/:job_id/steer → RecoveryProposal
         ├── iOS: Show RecoveryGate sheet
         │
         ├── User: "Approve" → POST /api/build/:job_id/recover
         │                     → Server creates profile via ASC API
         │                     → Server installs profile locally
         │                     → iOS retries archive step
         │                     → archive ──→ SUCCESS → upload → submit
         │
         └── User: "Reject"  → Pipeline halted at .failed state
```

### 9.3 Human Intervention Path (ASC Sign-In)

```
ascSignIn ──→ FAIL (403 Forbidden)
           │
           ├── iOS: diagnoseFailureMode() → .ascSignInRequired
           ├── iOS: POST /api/build/:job_id/steer → RecoveryProposal
           │     (action: manualIntervention, url: appstoreconnect.apple.com)
           ├── iOS: Show RecoveryGate sheet
           │
           ├── User: "Open Safari" button → opens ASC in Safari
           ├── User: Signs in, accepts terms
           ├── User: Returns to CodeGenie, taps "I've Done This — Retry"
           ├── iOS: Retries ascSignIn step
           └── ascSignIn ──→ SUCCESS → acceptAppleTerms (HUMAN) → ...
```

---

## 10. Implementation Plan

### Phase 1: Foundation (Week 1)
- [ ] Add `RecoveryProposal`, `RecoveryAction`, `FailureMode`, `ErrorContext`, `RecoveryRequest`, `RecoveryResult` types to Rust server (`builder/mod.rs`)
- [ ] Add `recovery_proposals` field to `AppState`
- [ ] Implement `POST /api/build/:job_id/steer` endpoint with `diagnose_failure()` function
- [ ] Implement `POST /api/build/:job_id/recover` endpoint with `apply_fix()` function
- [ ] Register new routes in `router()`
- [ ] Add Swift types: `RecoveryProposal`, `RecoveryAction`, `FailureMode`, `ErrorContext`, `RecoveryRequest`, `RecoveryResult`
- [ ] Add `steerRecovery()` and `recoverStep()` methods to `PipelineClient`

### Phase 2: Recovery Gate UI (Week 2)
- [ ] Implement `RecoveryGate.swift` SwiftUI view
- [ ] Add `.recovering(RecoveryProposal)` case to `PipelineStepStatus`
- [ ] Add `aiRecoveryProposal`, `retryCountByStep`, `markRecovering()`, `approveRecovery()`, `rejectRecovery()` to `PipelineRun`
- [ ] Integrate RecoveryGate sheet into BuildScreen/PipelineView
- [ ] Add `diagnoseFailureMode()` helper to pipeline execution code

### Phase 3: Recovery Implementations (Week 3)
- [ ] Implement `bump_build_number()` on the Rust side
- [ ] Implement `strip_icon_alpha()` on the Rust side
- [ ] Implement `unlock_keychain()` on the Rust side
- [ ] Implement `create_distribution_cert()` via ASC API on the Rust side
- [ ] Implement `create_provisioning_profile()` via ASC API on the Rust side
- [ ] Test each recovery scenario end-to-end

### Phase 4: Polish & Edge Cases (Week 4)
- [ ] Add retry count limits (max 3 retries per step)
- [ ] Add "give up" UI after max retries
- [ ] Add telemetry/logging for recovery attempts
- [ ] Handle network failures during steer/recover calls
- [ ] Add progress indicators during recovery (e.g., "Bumping build number…")
- [ ] Add SSE events for recovery progress so the client can show real-time status

---

## 11. Open Questions

1. **Should the AI steering use an LLM or rule-based diagnosis?** The current design uses pattern-matching (rule-based). An LLM could provide more nuanced diagnosis for novel errors, but adds latency and cost. **Recommendation:** Start rule-based, add LLM fallback for `unknown` failure modes in Phase 4.

2. **Should recovery be fully automatic (no human gate) for high-confidence fixes?** The current design requires human approval for all recoveries. For high-confidence, non-destructive fixes like build number bumps, we could auto-apply. **Recommendation:** Keep human gate for now; add auto-approve for confidence > 0.95 in a future iteration.

3. **How to handle cascading failures?** If archive fails, we fix it, and then upload fails, do we re-diagnose? Yes — each failure triggers a new steer call. The `retryCount` and `previousErrors` fields prevent infinite loops.

4. **Security of Keychain unlock?** Storing Keychain passwords in server-side config is risky. Consider using `security unlock-keychain` via CompanionBridge with the user's session password, or prompting the user in the RecoveryGate. **Recommendation:** Start with prompting the user to unlock Keychain manually (manualIntervention), then add CompanionBridge integration.

5. **Race conditions on retry?** If the user approves a fix while the server is still processing the original request, we need idempotency. The `proposal_id` in `RecoverRequest` ensures we apply the correct fix. **Recommendation:** Add proposal validation on the server side to prevent double-application.

---

## 12. Appendix: Existing API Routes

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/build` | Create a new build job |
| GET | `/api/build/:job_id/status` | Poll job status |
| GET | `/api/build/:job_id/stream` | SSE stream of build events |
| POST | `/api/build/:job_id/github` | Push to GitHub |
| POST | `/api/build/:job_id/patch` | Patch a bug |
| POST | `/api/build/:job_id/icon` | Generate app icon |
| GET | `/api/build/:job_id/perfection` | Run perfection audit |
| POST | `/api/build/:job_id/asc-metadata` | Generate ASC metadata |
| POST | `/api/build/:job_id/screenshots` | Take screenshots |
| POST | `/api/build/:job_id/upload` | Archive & upload to ASC |
| POST | `/api/build/:job_id/submit` | Submit for review |
| GET | `/api/build/:job_id/asc-signin` | Check ASC sign-in status |
| POST | `/api/build/:job_id/legal-pages` | Generate & publish legal pages |
| **POST** | **`/api/build/:job_id/steer`** | **NEW: AI steering diagnosis** |
| **POST** | **`/api/build/:job_id/recover`** | **NEW: Apply recovery action** |