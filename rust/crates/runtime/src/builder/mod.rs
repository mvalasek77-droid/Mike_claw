//! Builder module: orchestrates CodeGenie app builds received from the iPhone client.
//!
//! This module provides the types and logic for turning a [`BuildRequest`]
//! (sent by the `CodeGenie` iPhone app) into a working iOS project. The real
//! implementation creates project scaffolding, calls an AI to generate Swift
//! files, writes them to disk, compiles, and streams status events via a
//! tokio broadcast channel.

pub mod github;
pub mod orchestrator;
pub mod project;
pub mod prompts;

use serde::{Deserialize, Serialize};

/// The incoming request payload from the `CodeGenie` iPhone app.
///
/// Field names and types mirror the app's `AppSpec` schema so that JSON
/// deserialization "just works" with no client-side transformation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildRequest {
    /// App title – shown under the icon on the home screen.
    pub title: String,
    /// Natural-language description of what the app should do.
    pub prompt: String,
    /// Category hint (e.g. "productivity", "games", "social").
    pub category: String,
    /// Visual style hint (e.g. "minimal", "colorful").
    pub style: String,
    /// Target iOS version (e.g. "17.0").
    pub target_ios: String,
    /// Feature tags the user selected in the app.
    #[serde(default)]
    pub features: Vec<String>,
    /// Optional model override (e.g. "claude-sonnet-4-20250514").
    pub model: Option<String>,
    /// Optional auth mode preference.
    pub auth_mode: Option<String>,
    /// Optional API key supplied by the user (prefer env-var lookup).
    pub api_key: Option<String>,
}

/// Current status of a build job that the server is tracking.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BuildStatus {
    /// The server has accepted the request and is preparing a plan.
    Planning,
    /// Creating the Xcode project directory structure.
    Scaffolding,
    /// The AI is generating UI Swift files.
    GeneratingUI,
    /// The AI is generating logic / model Swift files.
    WiringLogic,
    /// Running lint / Static analysis on generated code.
    Linting,
    /// Compiling the project with xcodebuild / swift build.
    BuildingIPA,
    /// The build finished successfully.
    Completed,
    /// Something went wrong.
    Failed,
    // ── 5-Phase Build→Ship pipeline statuses ──────────────────────────
    /// Patching an existing build to fix a bug.
    Patching,
    /// Generating an app icon asset.
    GeneratingIcon,
    /// Running 9-axis quality probes (perfection audit).
    RunningPerfection,
    /// Generating App Store Connect metadata.
    GeneratingMetadata,
    /// Taking screenshots on-device.
    TakingScreenshots,
    /// Archiving and uploading the build to App Store Connect.
    UploadingASC,
    /// Submitting the build for App Store review.
    Submitting,
    /// Checking App Store Connect sign-in / app record.
    CheckingAscSignIn,
    /// Generating privacy policy & terms of use HTML.
    GeneratingLegalPages,
    /// Publishing legal pages to GitHub Pages.
    PublishingLegalPages,
}

impl std::fmt::Display for BuildStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Planning => write!(f, "planning"),
            Self::Scaffolding => write!(f, "scaffolding"),
            Self::GeneratingUI => write!(f, "generating_ui"),
            Self::WiringLogic => write!(f, "wiring_logic"),
            Self::Linting => write!(f, "linting"),
            Self::BuildingIPA => write!(f, "building_ipa"),
            Self::Completed => write!(f, "completed"),
            Self::Failed => write!(f, "failed"),
            Self::Patching => write!(f, "patching"),
            Self::GeneratingIcon => write!(f, "generating_icon"),
            Self::RunningPerfection => write!(f, "running_perfection"),
            Self::GeneratingMetadata => write!(f, "generating_metadata"),
            Self::TakingScreenshots => write!(f, "taking_screenshots"),
            Self::UploadingASC => write!(f, "uploading_asc"),
            Self::Submitting => write!(f, "submitting"),
            Self::CheckingAscSignIn => write!(f, "checking_asc_sign_in"),
            Self::GeneratingLegalPages => write!(f, "generating_legal_pages"),
            Self::PublishingLegalPages => write!(f, "publishing_legal_pages"),
        }
    }
}

/// A tracked build job stored in memory by the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildJob {
    /// Unique identifier for this build (UUIDv4).
    pub job_id: String,
    /// The original request that kicked off this build.
    pub request: BuildRequest,
    /// Local filesystem path where the project is being assembled.
    pub project_path: String,
    /// Current status of the build.
    pub status: BuildStatus,
    /// Human-readable error message when `status == Failed`.
    pub error: Option<String>,
}

impl BuildJob {
    /// Create a new job in `Planning` status.
    pub fn new(request: BuildRequest, project_path: String) -> Self {
        Self {
            job_id: uuid::Uuid::new_v4().to_string(),
            request,
            project_path,
            status: BuildStatus::Planning,
            error: None,
        }
    }
}

/// Events broadcast during a build pipeline run.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BuildEvent {
    /// The build transitioned to a new stage.
    #[serde(rename = "stage")]
    StageTransition {
        state: BuildStatus,
    },
    /// A log line emitted during the build.
    #[serde(rename = "log")]
    Log {
        message: String,
    },
    /// The build completed successfully with the given project path.
    #[serde(rename = "completed")]
    Completed {
        project_path: String,
    },
    /// The build failed with an error message.
    #[serde(rename = "failed")]
    Failed {
        error: String,
    },
    // ── Pipeline-specific events ───────────────────────────────────
    /// Patching completed: files were updated.
    #[serde(rename = "patched")]
    PatchCompleted {
        files_patched: Vec<String>,
    },
    /// Icon generation completed.
    #[serde(rename = "icon_generated")]
    IconGenerated {
        icon_path: String,
    },
    /// Perfection audit completed with 9-axis results.
    #[serde(rename = "perfection_completed")]
    PerfectionCompleted {
        axes: Vec<AxisResult>,
    },
    /// ASC metadata was generated.
    #[serde(rename = "metadata_generated")]
    MetadataGenerated,
    /// Screenshots were taken.
    #[serde(rename = "screenshots_taken")]
    ScreenshotsTaken {
        screenshot_paths: Vec<String>,
    },
    /// Build was archived and uploaded.
    #[serde(rename = "uploaded")]
    Uploaded {
        archive_path: String,
    },
    /// Build was submitted for review.
    #[serde(rename = "submitted")]
    Submitted,
    /// Detailed progress event for a sub-step within a pipeline phase.
    #[serde(rename = "pipeline_step")]
    PipelineStep {
        /// Which overall phase this step belongs to (e.g. "upload", "submit", "screenshots").
        phase: String,
        /// Which sub-step (e.g. "archiving", "exporting_ipa", "uploading_to_asc", "booting_simulator").
        step: String,
        /// Human-readable progress message.
        message: String,
    },
}

// ── Request types for the new endpoints ─────────────────────────────────

/// Request body for `POST /api/build/:job_id/patch`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatchRequest {
    /// Natural-language description of the bug to fix.
    pub bug_description: String,
    /// Optional list of specific files to patch. If omitted, the AI decides.
    #[serde(default)]
    pub files_to_edit: Option<Vec<String>>,
}

/// Request body for `POST /api/build/:job_id/icon`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IconRequest {
    /// Optional prompt describing the desired icon style.
    pub prompt: Option<String>,
}

/// Request body for `POST /api/build/:job_id/asc-metadata`.
///
/// No required fields — metadata is derived from the project.
/// This struct exists for future extensibility (e.g. overrides).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AscMetadataRequest {}

// ── Response types for the new endpoints ────────────────────────────────

/// Response for `POST /api/build/:job_id/patch`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatchResponse {
    pub job_id: String,
    pub status: String,
    pub files_patched: Vec<String>,
}

/// Response for `POST /api/build/:job_id/icon`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IconResponse {
    pub job_id: String,
    pub status: String,
    pub icon_path: String,
}

/// Response for `GET /api/build/:job_id/perfection`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerfectionResponse {
    pub job_id: String,
    pub status: String,
    pub axes: Vec<AxisResult>,
}

/// A single axis result in the perfection audit.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AxisResult {
    pub name: String,
    pub passed: u32,
    pub failed: u32,
    pub confidence: f64,
    pub recommendations: Vec<String>,
}

/// Intermediate type for parsing AI response — `job_id` is absent from AI output.
#[derive(Debug, Clone, Deserialize)]
pub struct AscMetadataAIOutput {
    #[serde(default)]
    pub job_id: String,
    pub name: String,
    pub subtitle: String,
    pub primary_category: String,
    pub keywords: Vec<String>,
    pub description: String,
    pub promotional_text: String,
    pub support_url: String,
    pub marketing_url: String,
    pub age_rating: String,
    pub privacy_policy_url: String,
}

/// Response for `POST /api/build/:job_id/asc-metadata`.
/// This is the API response type with `job_id` filled in by the server.
#[derive(Debug, Clone, Serialize)]
pub struct AscMetadataResponse {
    pub job_id: String,
    pub name: String,
    pub subtitle: String,
    pub primary_category: String,
    pub keywords: Vec<String>,
    pub description: String,
    pub promotional_text: String,
    pub support_url: String,
    pub marketing_url: String,
    pub age_rating: String,
    pub privacy_policy_url: String,
}

impl From<AscMetadataAIOutput> for AscMetadataResponse {
    fn from(ai: AscMetadataAIOutput) -> Self {
        Self {
            job_id: ai.job_id,
            name: ai.name,
            subtitle: ai.subtitle,
            primary_category: ai.primary_category,
            keywords: ai.keywords,
            description: ai.description,
            promotional_text: ai.promotional_text,
            support_url: ai.support_url,
            marketing_url: ai.marketing_url,
            age_rating: ai.age_rating,
            privacy_policy_url: ai.privacy_policy_url,
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenshotsResponse {
    pub job_id: String,
    pub status: String,
    pub screenshot_paths: Vec<String>,
}

/// Response for `POST /api/build/:job_id/upload`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadResponse {
    pub job_id: String,
    pub status: String,
    pub archive_path: String,
}

/// Response for `POST /api/build/:job_id/submit`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubmitResponse {
    pub job_id: String,
    pub status: String,
}

/// Response for `GET /api/build/:job_id/asc-signin`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AscSignInResponse {
    pub job_id: String,
    /// "signed_in" or "needs_sign_in"
    pub status: String,
    pub app_id: Option<String>,
    pub app_name: Option<String>,
    pub bundle_id: Option<String>,
    pub message: Option<String>,
}

/// Response for `POST /api/build/:job_id/legal-pages`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LegalPagesResponse {
    pub job_id: String,
    pub status: String,
    pub privacy_url: String,
    pub terms_url: String,
    pub repo_url: String,
}