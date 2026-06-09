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
}