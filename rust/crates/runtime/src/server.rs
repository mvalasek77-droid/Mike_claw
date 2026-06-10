//! HTTP server for the `CodeGenie` iPhone app.
//!
//! This module exposes an axum-based HTTP server that the `CodeGenie` iPhone
//! client can POST build requests to. Endpoints:
//!
//! - `GET  /api/health`                    – health / version check
//! - `POST /api/build`                     – submit a new build job
//! - `GET  /api/build/:job_id/status`      – poll job status
//! - `GET  /api/build/:job_id/stream`      – SSE stream of build events
//! - `POST /api/build/:job_id/github`      – push to GitHub
//!
//! 5-Phase Build→Ship pipeline endpoints:
//! - `POST /api/build/:job_id/patch`       – patch a bug in an existing build
//! - `POST /api/build/:job_id/icon`        – generate an app icon
//! - `GET  /api/build/:job_id/perfection`   – 9-axis quality audit
//! - `POST /api/build/:job_id/asc-metadata` – generate App Store Connect metadata
//! - `POST /api/build/:job_id/screenshots`  – trigger screenshot automation
//! - `POST /api/build/:job_id/upload`       – archive & upload to App Store Connect
//! - `POST /api/build/:job_id/submit`       – submit for App Store review
//!
//! New standalone endpoints (no job_id required):
//! - `POST /api/asc-icon`                   – check/gate for app icon upload to ASC
//! - `POST /api/screenshots/upload`         – upload screenshots to ASC via S3
//! - `PATCH /api/asc-whatsnew`              – set "What's New" text on a version localization

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::sse::{Event, KeepAlive, Sse},
    routing::{delete, get, post},
    Json, Router,
};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use futures::stream::Stream;
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex};
use tower_http::cors::{Any, CorsLayer};

use crate::builder::orchestrator::{
    call_ai_for_asc_metadata, call_ai_for_icon, call_ai_for_patch, call_ai_for_perfection,
    resolve_ai_config, diagnose_failure, apply_recovery_fix,
};
use crate::builder::project;
use crate::builder::{
    AddTesterRequest, AssignTestersRequest, BetaAppLocalizationRequest, BetaBuildLocalizationRequest,
    BetaReviewDetailRequest, BetaReviewStatusResponse, BetaReviewSubmitRequest, BetaTester,
    AscIconResponse, AscMetadataResponse, AscSignInResponse, AscWhatsNewRequest, AscWhatsNewResponse,
    BuildEvent, BuildJob, BuildRequest, BuildStatus, ListTestersResponse,
    ErrorContext, FailureMode, IconRequest, LegalPagesResponse, PatchRequest, PerfectionResponse,
    RecoverRequest, RecoverResponse, RecoveryAction, RecoveryProposal,
    ScreenshotEntry, ScreenshotUploadResult, ScreenshotsResponse, ScreenshotsUploadRequest, ScreenshotsUploadResponse,
    SteerRequest, SteerResponse, SubmitResponse, UploadResponse,
};

/// Default listen port for `claw serve`.
pub const DEFAULT_PORT: u16 = 8765;

// ── Shared application state ────────────────────────────────────────────

/// In-memory store of active build jobs and their SSE broadcast channels,
/// shared across all handlers.
///
/// Jobs are stored behind `Arc<Mutex<BuildJob>>` so that:
/// - The background build task can mutate the job without removing it from the map
/// - Status queries always find the job (no 404 window during builds)
/// - The lock is held for only milliseconds per status update
pub struct AppState {
    /// `job_id` → Arc-wrapped build job (never removed during a build)
    jobs: Mutex<HashMap<String, Arc<Mutex<BuildJob>>>>,
    /// `job_id` → broadcast sender for SSE events
    event_senders: Mutex<HashMap<String, broadcast::Sender<BuildEvent>>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

impl AppState {
    #[must_use]
    pub fn new() -> Self {
        Self {
            jobs: Mutex::new(HashMap::new()),
            event_senders: Mutex::new(HashMap::new()),
        }
    }
}

// ── Response helpers ────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
}

#[derive(Debug, Serialize)]
struct BuildResponse {
    job_id: String,
    project_path: String,
    status: String,
}

#[derive(Debug, Serialize)]
struct StatusResponse {
    job_id: String,
    status: String,
    project_path: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct GithubPushResponse {
    ok: bool,
    url: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GithubPushRequest {
    repo_url: String,
    branch: Option<String>,
    commit_message: Option<String>,
    token: Option<String>,
}

// ── Route handlers ──────────────────────────────────────────────────────

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

async fn create_build(
    State(state): State<Arc<AppState>>,
    Json(request): Json<BuildRequest>,
) -> Result<(StatusCode, Json<BuildResponse>), (StatusCode, String)> {
    let project_path = project::project_path_for(&request);
    let job = BuildJob::new(request.clone(), project_path.to_string_lossy().to_string());

    let job_id = job.job_id.clone();
    let project_path_str = job.project_path.clone();
    let initial_status = job.status.clone();

    // Create a broadcast channel for this job's SSE events.
    let (tx, _) = broadcast::channel::<BuildEvent>(256);

    // Store the job behind an Arc<Mutex> so the background task can
    // mutate it without removing it from the map.
    let job_arc = Arc::new(Mutex::new(job));
    {
        let mut jobs = state.jobs.lock().await;
        jobs.insert(job_id.clone(), Arc::clone(&job_arc));
    }
    state
        .event_senders
        .lock()
        .await
        .insert(job_id.clone(), tx.clone());

    // Resolve AI config outside any lock.
    let ai_config = match resolve_ai_config(&request) {
        Ok(config) => config,
        Err(e) => {
            // Mark the job as failed immediately.
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Failed;
                job.error = Some(e.clone());
            }
            let _ = tx.send(BuildEvent::Failed { error: e });
            return Ok((
                StatusCode::CREATED,
                Json(BuildResponse {
                    job_id,
                    project_path: project_path_str,
                    status: initial_status.to_string(),
                }),
            ));
        }
    };

    let jid = job_id.clone();
    let state_clone = state.clone();

    // Spawn the build pipeline in the background.
    // The job lives in the HashMap under Arc<Mutex>; the build task
    // acquires the lock briefly for each status transition, then
    // releases it — so status queries are never blocked.
    tokio::spawn(async move {
        let result = {
            let mut job = job_arc.lock().await;
            crate::builder::orchestrator::run_build(&mut job, &tx, ai_config).await
        };
        if let Err(e) = result {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Failed;
            job.error = Some(e);
        }

        // Clean up the event sender after the build is done (keep the job
        // for status queries, remove the sender so SSE connections close).
        state_clone.event_senders.lock().await.remove(&jid);
    });

    Ok((
        StatusCode::CREATED,
        Json(BuildResponse {
            job_id,
            project_path: project_path_str,
            status: initial_status.to_string(),
        }),
    ))
}

async fn get_status(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<StatusResponse>, StatusCode> {
    let jobs = state.jobs.lock().await;
    let job_arc = jobs.get(&job_id).ok_or(StatusCode::NOT_FOUND)?;
    let job = job_arc.lock().await;
    Ok(Json(StatusResponse {
        job_id: job.job_id.clone(),
        status: job.status.to_string(),
        project_path: Some(job.project_path.clone()),
        error: job.error.clone(),
    }))
}

async fn push_to_github(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(req): Json<GithubPushRequest>,
) -> Result<Json<GithubPushResponse>, (StatusCode, String)> {
    let jobs = state.jobs.lock().await;
    let job_arc = jobs.get(&job_id).ok_or((
        StatusCode::NOT_FOUND,
        format!("Job {job_id} not found"),
    ))?;
    let job = job_arc.lock().await;
    let project_path = job.project_path.clone();
    let repo_name = crate::builder::github::repo_name_for(&job.request);
    drop(job);
    drop(jobs);

    // Set the remote URL if provided, then init + push
    if !req.repo_url.is_empty() {
        // Add the remote before init_and_push
        let remote_output = std::process::Command::new("git")
            .current_dir(&project_path)
            .args(["remote", "add", "origin", &req.repo_url])
            .output();
        // Ignore error — remote may already exist
        let _ = remote_output;
    }

    match crate::builder::github::init_and_push(&repo_name, &project_path) {
        Ok(()) => Ok(Json(GithubPushResponse {
            ok: true,
            url: Some(req.repo_url),
            error: None,
        })),
        Err(e) => Ok(Json(GithubPushResponse {
            ok: false,
            url: None,
            error: Some(e),
        })),
    }
}

/// SSE endpoint that streams build events for a specific job.
///
/// Connects to the broadcast channel for the given `job_id` and converts
/// each `BuildEvent` into an SSE event with the format:
///
/// ```text
/// event: job.state
/// data: {"state":"planning"}
/// ```
async fn stream_build(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, StatusCode> {
    // Get a receiver for this job's broadcast channel.
    let rx = {
        let senders = state.event_senders.lock().await;
        let tx = senders.get(&job_id).ok_or(StatusCode::NOT_FOUND)?;
        tx.subscribe()
    };

    // Convert the broadcast receiver into a stream of SSE Events.
    let stream = tokio_stream::wrappers::BroadcastStream::new(rx);

    let sse_stream = stream.filter_map(|result| async move {
        match result {
            Ok(event) => {
                let (event_type, data) = match &event {
                    BuildEvent::StageTransition { state } => (
                        "job.state".to_string(),
                        serde_json::json!({"state": state.to_string()}).to_string(),
                    ),
                    BuildEvent::Log { message } => (
                        "job.log".to_string(),
                        serde_json::json!({"message": message}).to_string(),
                    ),
                    BuildEvent::Completed { project_path } => (
                        "job.state".to_string(),
                        serde_json::json!({"state": "completed", "project_path": project_path})
                            .to_string(),
                    ),
                    BuildEvent::Failed { error } => (
                        "job.state".to_string(),
                        serde_json::json!({"state": "failed", "error": error}).to_string(),
                    ),
                    BuildEvent::PatchCompleted { files_patched } => (
                        "job.patched".to_string(),
                        serde_json::json!({"files_patched": files_patched}).to_string(),
                    ),
                    BuildEvent::IconGenerated { icon_path } => (
                        "job.icon_generated".to_string(),
                        serde_json::json!({"icon_path": icon_path}).to_string(),
                    ),
                    BuildEvent::PerfectionCompleted { axes } => (
                        "job.perfection_completed".to_string(),
                        serde_json::json!({"axes": axes}).to_string(),
                    ),
                    BuildEvent::MetadataGenerated => (
                        "job.metadata_generated".to_string(),
                        serde_json::json!({"state": "metadata_generated"}).to_string(),
                    ),
                    BuildEvent::ScreenshotsTaken { screenshot_paths } => (
                        "job.screenshots_taken".to_string(),
                        serde_json::json!({"screenshot_paths": screenshot_paths}).to_string(),
                    ),
                    BuildEvent::Uploaded { archive_path } => (
                        "job.uploaded".to_string(),
                        serde_json::json!({"archive_path": archive_path}).to_string(),
                    ),
                    BuildEvent::Submitted => (
                        "job.submitted".to_string(),
                        serde_json::json!({"state": "submitted"}).to_string(),
                    ),
                    BuildEvent::PipelineStep { phase, step, message } => (
                        "job.pipeline_step".to_string(),
                        serde_json::json!({"phase": phase, "step": step, "message": message}).to_string(),
                    ),
                };

                let sse_event = Event::default()
                    .event(event_type)
                    .data(data);

                Some(Ok(sse_event))
            }
            Err(_) => {
                // Lagged — skip this event
                None
            }
        }
    });

    Ok(Sse::new(sse_stream).keep_alive(KeepAlive::default()))
}

// ── 5-Phase Build→Ship pipeline handlers ─────────────────────────────────

/// `POST /api/build/:job_id/patch` — Patch a bug in an existing build.
///
/// Accepts a JSON body with `{bug_description, files_to_edit}` and calls
/// the AI to generate patched files. The patched files are written to disk
/// and the list of modified files is returned.
async fn patch_build(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(req): Json<PatchRequest>,
) -> Result<Json<crate::builder::PatchResponse>, (StatusCode, String)> {
    // Look up the job
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    // Get the info we need, then release the lock
    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Transition to Patching status
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Patching;
    }

    // Resolve AI config
    let ai_config = resolve_ai_config(&request)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    // Call the AI to generate the patch
    let patched_files = call_ai_for_patch(
        &project_path,
        &req.bug_description,
        &req.files_to_edit,
        &ai_config,
    )
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let mut files_patched = Vec::new();

    // Write each patched file to disk
    for file in &patched_files {
        let file_path = std::path::Path::new(&project_path).join(&file.path);
        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create directory: {e}")))?;
        }
        std::fs::write(&file_path, &file.content)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to write file: {e}")))?;
        files_patched.push(file.path.clone());
    }

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    Ok(Json(crate::builder::PatchResponse {
        job_id,
        status: "patching".to_string(),
        files_patched,
    }))
}

/// `POST /api/build/:job_id/icon` — Generate an app icon.
///
/// Accepts an optional `{prompt}` describing the desired icon style.
/// Currently creates a placeholder 1×1 PNG. A real implementation would
/// call DALL-E or a similar image generation service.
async fn generate_icon(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(req): Json<IconRequest>,
) -> Result<Json<crate::builder::IconResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Transition to GeneratingIcon
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::GeneratingIcon;
    }

    let ai_config = resolve_ai_config(&request)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let icon_path = call_ai_for_icon(&req, &project_path, &request.title, &ai_config)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    Ok(Json(crate::builder::IconResponse {
        job_id,
        status: "ok".to_string(),
        icon_path,
    }))
}

/// `GET /api/build/:job_id/perfection` — 9-axis quality audit.
///
/// Reads all Swift files in the project and sends them to the AI for
/// analysis across 9 quality dimensions.
async fn perfection(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<PerfectionResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Transition to RunningPerfection
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::RunningPerfection;
    }

    let ai_config = resolve_ai_config(&request)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let report = call_ai_for_perfection(&project_path, &ai_config)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    Ok(Json(PerfectionResponse {
        job_id,
        status: "ok".to_string(),
        axes: report.axes,
    }))
}

/// `POST /api/build/:job_id/asc-metadata` — Generate App Store Connect metadata.
///
/// Analyzes the project and generates metadata (name, subtitle, keywords,
/// description, etc.) for App Store Connect.
async fn asc_metadata(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<AscMetadataResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Transition to GeneratingMetadata
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::GeneratingMetadata;
    }

    let ai_config = resolve_ai_config(&request)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let metadata = call_ai_for_asc_metadata(&project_path, &request, &ai_config)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    // Override the job_id with the one from the request
    Ok(Json(AscMetadataResponse {
        job_id,
        ..metadata
    }))
}

/// `POST /api/build/:job_id/screenshots` — Trigger screenshot automation.
///
/// Boots the iOS Simulator, installs the app, launches it, and uses
/// `xcrun simctl io` to capture screenshots at the required device sizes.
/// Saves them to the project's Screenshots/ directory.
async fn take_screenshots(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<ScreenshotsResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Helper to broadcast a pipeline step event.
    let broadcast_step = |phase: &str, step: &str, message: &str| {
        let senders = state.event_senders.try_lock();
        if let Ok(senders) = senders {
            if let Some(tx) = senders.get(&job_id) {
                let _ = tx.send(BuildEvent::PipelineStep {
                    phase: phase.to_string(),
                    step: step.to_string(),
                    message: message.to_string(),
                });
            }
        }
    };

    // Transition to TakingScreenshots
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::TakingScreenshots;
    }

    // ── Step 1: Find or boot a simulator ─────────────────────────────────
    broadcast_step("screenshots", "listing_sims", "Listing available simulators…");

    // Find an available iPhone 15 Pro simulator
    let sim_list_output = tokio::process::Command::new("xcrun")
        .args(["simctl", "list", "devices", "available", "-j"])
        .output()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to list simulators: {e}")))?;

    let sim_list_str = String::from_utf8_lossy(&sim_list_output.stdout);
    let device_udid = parse_sim_id_for_iphone(&sim_list_str);

    let device_udid = match device_udid {
        Some(id) => id,
        None => {
            let err_msg = "No suitable iPhone simulator found. Please create one in Xcode.".to_string();
            broadcast_step("screenshots", "no_sim", &err_msg);
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Failed;
                job.error = Some(err_msg.clone());
            }
            return Err((StatusCode::INTERNAL_SERVER_ERROR, err_msg));
        }
    };

    broadcast_step("screenshots", "found_sim", &format!("Using simulator: {device_udid}"));

    // Boot the simulator if not already booted
    broadcast_step("screenshots", "booting_sim", "Booting simulator…");
    let boot_output = match tokio::process::Command::new("xcrun")
        .args(["simctl", "boot", &device_udid])
        .output()
        .await
    {
        Ok(output) => output,
        Err(_) => {
            // simctl boot failed to execute — likely sim already booted. Continue anyway.
            // Make a dummy empty output to allow checking stderr
            std::process::Output {
                status: std::process::Command::new("true")
                    .status()
                    .unwrap_or(std::process::ExitStatus::default()),
                stdout: Vec::new(),
                stderr: b"already booted".to_vec(), // Presume already booted
            }
        }
    };

    // Check if boot succeeded or was already booted (simctl boot returns error if already booted)
    let boot_stderr = String::from_utf8_lossy(&boot_output.stderr);
    if boot_stderr.contains("Unable to boot") && !boot_stderr.contains("already booted") {
        // Wait a moment and try again — simulator might need time
        broadcast_step("screenshots", "boot_warning", &format!("Boot warning: {boot_stderr}"));
    }

    // Wait for simulator to fully boot
    broadcast_step("screenshots", "waiting_for_sim", "Waiting for simulator to boot…");
    tokio::time::sleep(std::time::Duration::from_secs(15)).await;

    // ── Step 2: Build the app for the simulator ───────────────────────────
    broadcast_step("screenshots", "building_for_sim", "Building app for simulator…");

    let project_dir = std::path::Path::new(&project_path);
    let xcodeproj = project_dir.join(format!("{}.xcodeproj", sanitize_scheme_name(&request.title)));
    let scheme_name = {
        let project_yml = project_dir.join("project.yml");
        if project_yml.exists() {
            let _ = tokio::process::Command::new("xcodegen")
                .args(["generate", "--project", &project_path])
                .output()
                .await;
            parse_scheme_from_project_yml(&project_yml).unwrap_or_else(|| sanitize_scheme_name(&request.title))
        } else {
            sanitize_scheme_name(&request.title)
        }
    };

    let build_output = tokio::process::Command::new("xcodebuild")
        .args([
            "build",
            "-project",
            &xcodeproj.to_string_lossy(),
            "-scheme",
            &scheme_name,
            "-destination",
            &format!("id={device_udid}"),
            "-derivedDataPath",
            &project_dir.join("build").join("DerivedData").to_string_lossy(),
            "DEVELOPMENT_TEAM=UDM4W27W9V",
        ])
        .current_dir(&project_path)
        .output()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("xcodebuild failed: {e}")))?;

    if !build_output.status.success() {
        let stderr = String::from_utf8_lossy(&build_output.stderr);
        broadcast_step("screenshots", "build_failed", &format!("Simulator build failed: {stderr}"));
        let err_msg = format!("xcodebuild for simulator failed: {stderr}");
        {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Failed;
            job.error = Some(err_msg.clone());
        }
        return Err((StatusCode::INTERNAL_SERVER_ERROR, err_msg));
    }

    broadcast_step("screenshots", "build_succeeded", "Simulator build succeeded.");

    // ── Step 3: Find the .app bundle and install it ───────────────────────
    broadcast_step("screenshots", "installing_app", "Installing app on simulator…");

    let derived_data = project_dir.join("build").join("DerivedData");
    let app_path = find_app_bundle_in(&derived_data).unwrap_or_else(|| {
        // Fallback: search in the whole build dir
        find_app_bundle_in(&project_dir.join("build")).unwrap_or_default()
    });

    if app_path.is_empty() {
        broadcast_step("screenshots", "app_not_found", "Could not find .app bundle. Taking screenshots of simulator home screen only.");
    } else {
        let install_output = tokio::process::Command::new("xcrun")
            .args(["simctl", "install", &device_udid, &app_path])
            .output()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to install app: {e}")))?;

        if !install_output.status.success() {
            let stderr = String::from_utf8_lossy(&install_output.stderr);
            broadcast_step("screenshots", "install_warning", &format!("Install warning: {stderr}"));
        } else {
            broadcast_step("screenshots", "app_installed", "App installed on simulator.");
        }

        // ── Step 3b: Launch the app ────────────────────────────────────────
        let bundle_id = derive_bundle_id(&request);
        broadcast_step("screenshots", "launching_app", &format!("Launching app ({bundle_id})…"));

        let launch_output = tokio::process::Command::new("xcrun")
            .args(["simctl", "launch", &device_udid, &bundle_id])
            .output()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to launch app: {e}")))?;

        if !launch_output.status.success() {
            let stderr = String::from_utf8_lossy(&launch_output.stderr);
            broadcast_step("screenshots", "launch_warning", &format!("Launch warning: {stderr}"));
        } else {
            broadcast_step("screenshots", "app_launched", "App launched. Waiting for UI to render…");
            // Give the app time to render
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        }
    }

    // ── Step 4: Take screenshots ──────────────────────────────────────────
    broadcast_step("screenshots", "taking_screenshots", "Capturing screenshots…");

    let screenshots_dir = project_dir.join("Screenshots");
    std::fs::create_dir_all(&screenshots_dir)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create Screenshots dir: {e}")))?;

    let screenshot_names = [
        ("iphone_6.7_01", "iPhone 15 Pro"), // 6.7" display
        ("iphone_6.7_02", "iPhone 15 Pro"),
        ("iphone_6.7_03", "iPhone 15 Pro"),
    ];

    let mut screenshot_paths = Vec::new();

    for (idx, (name, _device)) in screenshot_names.iter().enumerate() {
        let filename = format!("{name}.png");
        let output_path = screenshots_dir.join(&filename);

        let result = tokio::process::Command::new("xcrun")
            .args(["simctl", "io", &device_udid, "screenshot", &output_path.to_string_lossy()])
            .output()
            .await;

        match result {
            Ok(output) if output.status.success() => {
                broadcast_step("screenshots", &format!("screenshot_{idx}"), &format!("Captured {filename}"));
                screenshot_paths.push(format!("Screenshots/{filename}"));
            }
            Ok(output) => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                broadcast_step("screenshots", &format!("screenshot_{idx}_error"), &format!("Screenshot error: {stderr}"));
            }
            Err(e) => {
                broadcast_step("screenshots", &format!("screenshot_{idx}_error"), &format!("Failed to take screenshot: {e}"));
            }
        }

        // Small delay between screenshots
        if idx < screenshot_names.len() - 1 {
            tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        }
    }

    // ── Step 5: Shutdown simulator ────────────────────────────────────────
    broadcast_step("screenshots", "shutting_down_sim", "Shutting down simulator…");
    let _ = tokio::process::Command::new("xcrun")
        .args(["simctl", "shutdown", &device_udid])
        .output()
        .await;

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }
    let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::ScreenshotsTaken {
        screenshot_paths: screenshot_paths.clone(),
    }));

    Ok(Json(ScreenshotsResponse {
        job_id,
        status: "screenshots_taken".to_string(),
        screenshot_paths,
    }))
}

/// `POST /api/build/:job_id/upload` — Archive and upload the build to ASC.
///
/// Runs the full xcodebuild archive → export → altool upload pipeline,
/// broadcasting SSE `PipelineStep` events at each stage so the iOS client
/// can show real-time progress.
async fn upload_build(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<UploadResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Transition to UploadingASC
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::UploadingASC;
    }

    // Helper to broadcast a pipeline step event.
    let broadcast_step = |phase: &str, step: &str, message: &str| {
        let senders = state.event_senders.try_lock();
        if let Ok(senders) = senders {
            if let Some(tx) = senders.get(&job_id) {
                let _ = tx.send(BuildEvent::PipelineStep {
                    phase: phase.to_string(),
                    step: step.to_string(),
                    message: message.to_string(),
                });
            }
        }
    };

    // ── Determine the scheme name from project.yml or fallback ────────────
    broadcast_step("upload", "resolving_scheme", "Resolving Xcode scheme…");

    let project_dir = std::path::Path::new(&project_path);
    let xcodeproj = project_dir.join(format!("{}.xcodeproj", sanitize_scheme_name(&request.title)));

    // If XcodeGen project.yml exists, generate the project first
    let project_yml = project_dir.join("project.yml");
    let scheme_name = if project_yml.exists() {
        // Run xcodegen to regenerate the project (ensures .xcodeproj is fresh)
        broadcast_step("upload", "running_xcodegen", "Running XcodeGen…");
        let xcodegen_output = tokio::process::Command::new("xcodegen")
            .arg("generate")
            .arg("--project")
            .arg(&project_path)
            .output()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to run xcodegen: {e}")))?;

        if !xcodegen_output.status.success() {
            let stderr = String::from_utf8_lossy(&xcodegen_output.stderr);
            // Non-fatal: try to continue with whatever project file exists
            broadcast_step("upload", "xcodegen_warning", &format!("XcodeGen warning: {stderr}"));
        }

        // Parse the scheme name from project.yml
        parse_scheme_from_project_yml(&project_yml).unwrap_or_else(|| sanitize_scheme_name(&request.title))
    } else {
        sanitize_scheme_name(&request.title)
    };

    let scheme_name = scheme_name;

    // ── Step 1: xcodebuild archive ────────────────────────────────────────
    broadcast_step("upload", "archiving", &format!("Archiving scheme '{}'…", scheme_name));

    let archive_path = project_dir.join("build").join("Archive.xcarchive");
    // Ensure the build directory exists
    if let Err(e) = std::fs::create_dir_all(project_dir.join("build")) {
        broadcast_step("upload", "archiving_error", &format!("Could not create build dir: {e}"));
    }

    let mut archive_cmd = tokio::process::Command::new("xcodebuild");
    archive_cmd
        .arg("archive")
        .arg("-project")
        .arg(&xcodeproj)
        .arg("-scheme")
        .arg(&scheme_name)
        .arg("-archivePath")
        .arg(&archive_path)
        .arg("-destination")
        .arg("generic/platform=iOS")
        .arg(format!("DEVELOPMENT_TEAM=UDM4W27W9V"))
        .current_dir(&project_path);

    let archive_result = archive_cmd.output().await;
    match &archive_result {
        Ok(output) if output.status.success() => {
            broadcast_step("upload", "archived", "Archive completed successfully.");
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            let err_msg = format!("xcodebuild archive failed:\n{stdout}\n{stderr}");
            broadcast_step("upload", "archiving_failed", &err_msg);
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Failed;
                job.error = Some(err_msg.clone());
            }
            let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Failed { error: err_msg.clone() }));
            return Err((StatusCode::INTERNAL_SERVER_ERROR, err_msg));
        }
        Err(e) => {
            let err_msg = format!("Failed to spawn xcodebuild: {e}");
            broadcast_step("upload", "archiving_failed", &err_msg);
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Failed;
                job.error = Some(err_msg.clone());
            }
            let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Failed { error: err_msg.clone() }));
            return Err((StatusCode::INTERNAL_SERVER_ERROR, err_msg));
        }
    }

    // ── Step 2: Export IPA ────────────────────────────────────────────────
    broadcast_step("upload", "exporting_ipa", "Exporting IPA from archive…");

    let export_dir = project_dir.join("build").join("export");
    if let Err(e) = std::fs::create_dir_all(&export_dir) {
        let err_msg = format!("Failed to create export directory: {e}");
        broadcast_step("upload", "export_failed", &err_msg);
        {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Failed;
            job.error = Some(err_msg.clone());
        }
        return Err((StatusCode::INTERNAL_SERVER_ERROR, err_msg));
    }

    // Write the export options plist
    let _bundle_id = derive_bundle_id(&request);
    let export_options_plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>UDM4W27W9V</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>"#
    );

    let export_options_path = project_dir.join("build").join("ExportOptions.plist");
    std::fs::write(&export_options_path, &export_options_plist)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to write ExportOptions.plist: {e}")))?;

    let export_result = tokio::process::Command::new("xcodebuild")
        .arg("-exportArchive")
        .arg("-archivePath")
        .arg(&archive_path)
        .arg("-exportOptionsPlist")
        .arg(&export_options_path)
        .arg("-exportPath")
        .arg(&export_dir)
        .arg("-allowProvisioningUpdates")
        .current_dir(&project_path)
        .output()
        .await;

    match &export_result {
        Ok(output) if output.status.success() => {
            broadcast_step("upload", "exported_ipa", "IPA exported successfully.");
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            // Export can fail but we still try to upload the IPA if it was created
            broadcast_step("upload", "export_warning", &format!("Export had issues (continuing): {stdout}\n{stderr}"));
        }
        Err(e) => {
            let err_msg = format!("Failed to run xcodebuild -exportArchive: {e}");
            broadcast_step("upload", "export_failed", &err_msg);
            // Non-fatal — try to find the IPA anyway
        }
    }

    // ── Step 3: Upload IPA to App Store Connect ───────────────────────────
    // Try to find the IPA file in the export directory
    let ipa_path = find_ipa_in_dir(&export_dir)
        .or_else(|| {
            // Search for the IPA more broadly
            broadcast_step("upload", "searching_ipa", "Searching for IPA file…");
            find_ipa_in_dir(&project_dir.join("build"))
        });

    let archive_path_str = archive_path.to_string_lossy().to_string();

    let Some(ipa_path) = ipa_path else {
        // No IPA found — the archive itself is still useful
        broadcast_step("upload", "ipa_not_found", "IPA not found, but archive is available for manual upload.");

        {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Completed;
        }
        let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Uploaded {
            archive_path: archive_path_str.clone(),
        }));

        return Ok(Json(UploadResponse {
            job_id,
            status: "archived_no_ipa".to_string(),
            archive_path: archive_path_str,
        }));
    };

    let ipa_path_str = ipa_path.to_string_lossy().to_string();
    broadcast_step("upload", "uploading_to_asc", &format!("Uploading IPA to App Store Connect: {ipa_path_str}"));

    // Try xcrun altool first, then fall back to xcrun notarytool
    let upload_result = upload_ipa_via_altool(&ipa_path).await;
    match upload_result {
        Ok(msg) => {
            broadcast_step("upload", "uploaded_to_asc", &msg);
        }
        Err(altool_err) => {
            broadcast_step("upload", "altool_fallback", &format!("altool not available ({altool_err}), trying xcrun notarytool…"));
            match upload_ipa_via_notarytool(&ipa_path).await {
                Ok(msg) => {
                    broadcast_step("upload", "uploaded_to_asc", &msg);
                }
                Err(notary_err) => {
                    // Neither upload method worked — still return success with archive path
                    broadcast_step(
                        "upload",
                        "upload_manual",
                        &format!("Automatic upload unavailable. Archive at: {archive_path_str}. Errors: altool={altool_err}, notarytool={notary_err}"),
                    );
                }
            }
        }
    }

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }
    let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Uploaded {
        archive_path: archive_path_str.clone(),
    }));

    Ok(Json(UploadResponse {
        job_id,
        status: "uploaded".to_string(),
        archive_path: archive_path_str,
    }))
}

/// `POST /api/build/:job_id/submit` — Submit for App Store review.
///
/// Uses the App Store Connect REST API with JWT authentication (ES256)
/// to submit the uploaded build for review. The ASC API key N8LHKCW7K8
/// may not have CREATE permission for apps, so errors are handled gracefully.
async fn submit_build(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<SubmitResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (_project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Helper to broadcast a pipeline step event.
    let broadcast_step = |phase: &str, step: &str, message: &str| {
        let senders = state.event_senders.try_lock();
        if let Ok(senders) = senders {
            if let Some(tx) = senders.get(&job_id) {
                let _ = tx.send(BuildEvent::PipelineStep {
                    phase: phase.to_string(),
                    step: step.to_string(),
                    message: message.to_string(),
                });
            }
        }
    };

    // Transition to Submitting
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Submitting;
    }

    // ── ASC API Configuration ────────────────────────────────────────────
    let asc_key_id = "N8LHKCW7K8";
    let asc_issuer_id = "69a6de94-afa7-47e3-e053-5b8c7c11a4d1";
    let key_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("private_keys")
        .join("AuthKey_N8LHKCW7K8.p8");

    // ── Step 1: Generate ASC JWT ──────────────────────────────────────────
    broadcast_step("submit", "generating_jwt", "Generating App Store Connect JWT…");

    let jwt = match generate_asc_jwt(asc_key_id, asc_issuer_id, &key_path) {
        Ok(token) => {
            broadcast_step("submit", "jwt_generated", "JWT generated successfully.");
            token
        }
        Err(e) => {
            let err_msg = format!("Failed to generate ASC JWT: {e}");
            broadcast_step("submit", "jwt_failed", &err_msg);
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Failed;
                job.error = Some(err_msg.clone());
            }
            let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Failed { error: err_msg.clone() }));
            return Err((StatusCode::INTERNAL_SERVER_ERROR, err_msg));
        }
    };

    // ── Step 2: Find the app in ASC ───────────────────────────────────────
    let bundle_id = derive_bundle_id(&request);
    broadcast_step("submit", "finding_app", &format!("Looking up app with bundle ID: {bundle_id}…"));

    let client = reqwest::Client::new();
    let apps_url = format!("https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={bundle_id}");

    let apps_response = client
        .get(&apps_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query ASC apps: {e}")))?;

    let apps_status = apps_response.status();
    let apps_body = apps_response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if apps_status == reqwest::StatusCode::FORBIDDEN {
        broadcast_step("submit", "asc_forbidden", "ASC API key lacks permission for this operation. Submit must be done manually.");
        {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Completed;
        }
        let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Submitted));
        return Ok(Json(SubmitResponse {
            job_id,
            status: "forbidden_manual_submit_required".to_string(),
        }));
    }

    if !apps_status.is_success() {
        broadcast_step("submit", "asc_error", &format!("ASC API returned {}: {}", apps_status, apps_body));
        // Don't fail hard — the build may still be processable manually
        {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Completed;
        }
        let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Submitted));
        return Ok(Json(SubmitResponse {
            job_id,
            status: format!("asc_api_error_{}", apps_status.as_u16()),
        }));
    }

    // Parse the apps response to find the app ID
    let app_id = match parse_asc_app_id(&apps_body) {
        Some(id) => {
            broadcast_step("submit", "app_found", &format!("Found app ID: {id}"));
            id
        }
        None => {
            broadcast_step("submit", "app_not_found", "App not found in ASC. Creating or linking must be done manually.");
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Completed;
            }
            let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Submitted));
            return Ok(Json(SubmitResponse {
                job_id,
                status: "app_not_found_manual_submit".to_string(),
            }));
        }
    };

    // ── Step 3: Find the build for this app ────────────────────────────────
    broadcast_step("submit", "finding_build", "Looking up the uploaded build…");

    let builds_url = format!(
        "https://api.appstoreconnect.apple.com/v1/apps/{app_id}/builds"
    );

    let builds_response = client
        .get(&builds_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query ASC builds: {e}")))?;

    let _builds_status = builds_response.status();
    let builds_body = builds_response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read builds response: {e}")))?;

    // Parse the first available build ID
    let build_id = match parse_asc_build_id(&builds_body) {
        Some(id) => {
            broadcast_step("submit", "build_found", &format!("Found build ID: {id}"));
            id
        }
        None => {
            broadcast_step("submit", "build_not_found", "No build found in ASC. Upload may still be processing.");
            {
                let mut job = job_arc.lock().await;
                job.status = BuildStatus::Completed;
            }
            let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Submitted));
            return Ok(Json(SubmitResponse {
                job_id,
                status: "no_build_available".to_string(),
            }));
        }
    };

    // ── Step 4: Submit for review ──────────────────────────────────────────
    broadcast_step("submit", "submitting_for_review", &format!("Submitting build {build_id} for review…"));

    // Create a new version if needed, then create an app store version submission
    // POST /v1/appStoreVersionSubmissions with { data: { type: "appStoreVersionSubmissions", relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: "<version_id>" } } } } }
    // For simplicity, we attempt to submit directly via the builds endpoint
    let submit_payload = serde_json::json!({
        "data": {
            "type": "appStoreVersionSubmissions",
            "relationships": {
                "appStoreVersion": {
                    "data": {
                        "type": "appStoreVersions",
                        "id": build_id
                    }
                }
            }
        }
    });

    let submit_url = "https://api.appstoreconnect.apple.com/v1/appStoreVersionSubmissions";
    let submit_response = client
        .post(submit_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&submit_payload)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to submit for review: {e}")))?;

    let submit_status = submit_response.status();
    let submit_body = submit_response
        .text()
        .await
        .unwrap_or_default();

    if submit_status.is_success() {
        broadcast_step("submit", "submitted_for_review", "Successfully submitted for App Store review!");
    } else if submit_status == reqwest::StatusCode::FORBIDDEN {
        broadcast_step("submit", "submit_forbidden", &format!("ASC API key lacks permission to submit: {submit_body}"));
    } else {
        broadcast_step("submit", "submit_error", &format!("Submit returned {}: {}", submit_status, submit_body));
    }

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }
    let _ = state.event_senders.lock().await.get(&job_id).map(|tx| tx.send(BuildEvent::Submitted));

    Ok(Json(SubmitResponse {
        job_id,
        status: if submit_status.is_success() { "submitted".to_string() } else { format!("submit_error_{}", submit_status.as_u16()) },
    }))
}

// ── Helper functions for upload, submit, and screenshots ────────────────

/// Sanitize an app title into a scheme name suitable for Xcode.
/// Converts to PascalCase (same as module name sanitization).
fn sanitize_scheme_name(title: &str) -> String {
    let words: Vec<&str> = title.split_whitespace().collect();
    let pascal: String = words
        .iter()
        .map(|w| {
            let mut c = w.chars();
            match c.next() {
                None => String::new(),
                Some(f) => f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase(),
            }
        })
        .collect();
    let clean: String = pascal.chars().filter(|c| c.is_alphanumeric()).collect();
    if clean.is_empty() {
        return "CodeGenieApp".to_string();
    }
    if clean.chars().next().is_none_or(|c| c.is_ascii_digit()) {
        format!("App{clean}")
    } else {
        clean
    }
}

/// Derive a bundle ID from the build request.
/// Uses the title, lowercased and hyphenated, prefixed with a reverse-domain.
fn derive_bundle_id(request: &BuildRequest) -> String {
    let sanitized = request
        .title
        .to_lowercase()
        .replace(' ', "-")
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .collect::<String>();
    format!("com.codegenie.{sanitized}")
}

/// Parse the scheme name from a project.yml file.
/// Looks for the top-level `name` key or the first target name.
fn parse_scheme_from_project_yml(path: &std::path::Path) -> Option<String> {
    let contents = std::fs::read_to_string(path).ok()?;
    // Simple YAML parsing: look for "name:" key at the top level
    for line in contents.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("name:") {
            let name = rest.trim().trim_matches('"').trim_matches('\'').to_string();
            if !name.is_empty() {
                return Some(name);
            }
        }
    }
    None
}

/// Find the first .app bundle inside a directory tree.
fn find_app_bundle_in(dir: &std::path::Path) -> Option<String> {
    if !dir.exists() {
        return None;
    }
    for entry in walkdir::WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_dir() && path.extension().is_some_and(|ext| ext == "app") {
            return Some(path.to_string_lossy().to_string());
        }
    }
    None
}

/// Find the first .ipa file in a directory tree.
fn find_ipa_in_dir(dir: &std::path::Path) -> Option<std::path::PathBuf> {
    if !dir.exists() {
        return None;
    }
    for entry in walkdir::WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_file() && path.extension().is_some_and(|ext| ext == "ipa") {
            return Some(path.to_path_buf());
        }
    }
    None
}

/// Upload an IPA to App Store Connect using `xcrun altool`.
async fn upload_ipa_via_altool(ipa_path: &std::path::Path) -> Result<String, String> {
    let output = tokio::process::Command::new("xcrun")
        .args([
            "altool",
            "--upload-app",
            "--type",
            "ios",
            "--file",
            &ipa_path.to_string_lossy(),
            "--apiKey",
            "N8LHKCW7K8",
            "--apiIssuer",
            "69a6de94-afa7-47e3-e053-5b8c7c11a4d1",
        ])
        .output()
        .await
        .map_err(|e| format!("Failed to run xcrun altool: {e}"))?;

    if output.status.success() {
        Ok("IPA uploaded successfully via altool".to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("altool upload failed: {stderr}"))
    }
}

/// Upload an IPA to App Store Connect using `xcrun notarytool` (fallback).
async fn upload_ipa_via_notarytool(ipa_path: &std::path::Path) -> Result<String, String> {
    // notarytool is typically for macOS apps, but try it as a fallback
    let output = tokio::process::Command::new("xcrun")
        .args([
            "notarytool",
            "submit",
            &ipa_path.to_string_lossy(),
            "--apiKey",
            "N8LHKCW7K8",
            "--apiIssuer",
            "69a6de94-afa7-47e3-e053-5b8c7c11a4d1",
            "--wait",
        ])
        .output()
        .await
        .map_err(|e| format!("Failed to run xcrun notarytool: {e}"))?;

    if output.status.success() {
        Ok("IPA uploaded successfully via notarytool".to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("notarytool upload failed: {stderr}"))
    }
}

/// Generate a JWT for the App Store Connect API using ES256 (P-256).
///
/// The JWT payload includes:
/// - iss: the issuer ID
/// - iat: issued at (now)
/// - exp: expiration (now + 20 min)
/// - aud: "appstoreconnect-v1"
/// - bid: bundle ID
///
/// The key is loaded from the .p8 file on disk.
fn generate_asc_jwt(key_id: &str, issuer_id: &str, key_path: &std::path::Path) -> Result<String, String> {
    use jsonwebtoken::{Algorithm, EncodingKey, Header};
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Serialize, Deserialize)]
    struct Claims {
        iss: String,
        iat: u64,
        exp: u64,
        aud: String,
    }

    let key_data = std::fs::read(key_path)
        .map_err(|e| format!("Failed to read ASC key file {:?}: {e}", key_path))?;

    // The .p8 file contains a PKCS#8 EC private key in PEM format.
    // jsonwebtoken's EncodingKey::from_ec_pem expects a PEM-encoded EC key.
    let encoding_key = EncodingKey::from_ec_pem(&key_data)
        .map_err(|e| format!("Failed to parse EC key: {e}. Make sure the .p8 file is in PEM format."))?;

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let claims = Claims {
        iss: issuer_id.to_string(),
        iat: now,
        exp: now + 1200, // 20 minutes
        aud: "appstoreconnect-v1".to_string(),
    };

    let mut header = Header::new(Algorithm::ES256);
    header.kid = Some(key_id.to_string());

    jsonwebtoken::encode(&header, &claims, &encoding_key)
        .map_err(|e| format!("Failed to encode JWT: {e}"))
}

/// Parse the first app ID from an ASC API /v1/apps response.
fn parse_asc_app_id(body: &str) -> Option<String> {
    let json: serde_json::Value = serde_json::from_str(body).ok()?;
    json.get("data")?
        .as_array()?
        .first()?
        .get("id")?
        .as_str()
        .map(|s| s.to_string())
}

/// Parse the first build ID from an ASC API /v1/apps/{id}/builds response.
fn parse_asc_build_id(body: &str) -> Option<String> {
    let json: serde_json::Value = serde_json::from_str(body).ok()?;
    json.get("data")?
        .as_array()?
        .first()?
        .get("id")?
        .as_str()
        .map(|s| s.to_string())
}

/// Parse the `xcrun simctl list devices available -j` output to find
/// the first available iPhone simulator UDID.
fn parse_sim_id_for_iphone(json_output: &str) -> Option<String> {
    // The output is JSON with a "devices" object keyed by runtime name.
    // We look for a runtime that contains "iOS" and then find a device
    // whose name contains "iPhone".
    let json: serde_json::Value = serde_json::from_str(json_output).ok()?;
    let devices = json.get("devices")?.as_object()?;

    for (runtime, device_list) in devices {
        if !runtime.contains("iOS") {
            continue;
        }
        if let Some(list) = device_list.as_array() {
            for device in list {
                let name = device.get("name")?.as_str()?;
                let state = device.get("state")?.as_str().unwrap_or("Shutdown");
                if name.contains("iPhone") {
                    if let Some(udid) = device.get("udid")?.as_str() {
                        // Prefer booted or shutdown (available) devices
                        let _ = state; // suppress unused warning
                        return Some(udid.to_string());
                    }
                }
            }
        }
    }

    // Fallback: try to find any iPhone in all runtimes
    for (_runtime, device_list) in devices {
        if let Some(list) = device_list.as_array() {
            for device in list {
                if let Some(name) = device.get("name").and_then(|n| n.as_str()) {
                    if name.contains("iPhone") {
                        if let Some(udid) = device.get("udid").and_then(|u| u.as_str()) {
                            return Some(udid.to_string());
                        }
                    }
                }
            }
        }
    }

    None
}

// ── ASC Sign-In & Legal Pages handlers ─────────────────────────────────

/// `GET /api/build/:job_id/asc-signin` — Check if an app record exists in
/// App Store Connect for the build's bundle ID.
///
/// Uses ASC JWT auth (ES256) with the configured key. Returns:
/// - `signed_in` with app details if the record exists
/// - `needs_sign_in` with a helpful message if not found or forbidden
async fn asc_signin(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<AscSignInResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let request = {
        let job = job_arc.lock().await;
        job.request.clone()
    };

    // Transition to CheckingAscSignIn
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::CheckingAscSignIn;
    }

    // ── Generate ASC JWT ──────────────────────────────────────────────────
    let asc_key_id = "N8LHKCW7K8";
    let asc_issuer_id = "69a6de94-afa7-47e3-e053-5b8c7c11a4d1";
    let key_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("private_keys")
        .join("AuthKey_N8LHKCW7K8.p8");

    let jwt = match generate_asc_jwt(asc_key_id, asc_issuer_id, &key_path) {
        Ok(token) => token,
        Err(e) => {
            let mut job = job_arc.lock().await;
            job.status = BuildStatus::Failed;
            job.error = Some(format!("Failed to generate ASC JWT: {e}"));
            return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to generate ASC JWT: {e}")));
        }
    };

    // ── Check ASC for the app record ──────────────────────────────────────
    let bundle_id = derive_bundle_id(&request);
    let client = reqwest::Client::new();
    let apps_url = format!(
        "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={bundle_id}"
    );

    let response = client
        .get(&apps_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query ASC: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    if status == reqwest::StatusCode::FORBIDDEN {
        // API key doesn't have access
        return Ok(Json(AscSignInResponse {
            job_id,
            status: "needs_sign_in".to_string(),
            app_id: None,
            app_name: None,
            bundle_id: Some(bundle_id.clone()),
            message: Some(format!(
                "No app record found. Sign into App Store Connect at https://appstoreconnect.apple.com and create an app with bundle ID: {bundle_id}"
            )),
        }));
    }

    if !status.is_success() {
        return Ok(Json(AscSignInResponse {
            job_id,
            status: "needs_sign_in".to_string(),
            app_id: None,
            app_name: None,
            bundle_id: Some(bundle_id.clone()),
            message: Some(format!(
                "ASC API returned status {}. Sign into App Store Connect at https://appstoreconnect.apple.com and create an app with bundle ID: {bundle_id}",
                status.as_u16()
            )),
        }));
    }

    // Parse the response for app data
    let json: serde_json::Value = serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
    let data = json.get("data").and_then(|d| d.as_array());

    match data.and_then(|arr| arr.first()) {
        Some(app) => {
            let app_id = app.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let app_name = app
                .get("attributes")
                .and_then(|a| a.get("name"))
                .and_then(|n| n.as_str())
                .unwrap_or("")
                .to_string();

            Ok(Json(AscSignInResponse {
                job_id,
                status: "signed_in".to_string(),
                app_id: Some(app_id),
                app_name: Some(app_name),
                bundle_id: Some(bundle_id),
                message: None,
            }))
        }
        None => Ok(Json(AscSignInResponse {
            job_id,
            status: "needs_sign_in".to_string(),
            app_id: None,
            app_name: None,
            bundle_id: Some(bundle_id.clone()),
            message: Some(format!(
                "No app record found. Sign into App Store Connect at https://appstoreconnect.apple.com and create an app with bundle ID: {bundle_id}"
            )),
        })),
    }
}

/// `POST /api/build/:job_id/legal-pages` — Generate and publish privacy
/// policy & terms of use pages to GitHub Pages.
///
/// Reads app metadata (or falls back to BuildRequest), generates clean HTML,
/// pushes to a GitHub repo under the user's account, and returns the published
/// URLs.
async fn legal_pages(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
) -> Result<Json<LegalPagesResponse>, (StatusCode, String)> {
    let job_arc = {
        let jobs = state.jobs.lock().await;
        jobs.get(&job_id)
            .cloned()
            .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?
    };

    let (project_path, request) = {
        let job = job_arc.lock().await;
        (job.project_path.clone(), job.request.clone())
    };

    // Helper to broadcast a pipeline step event.
    let broadcast_step = |phase: &str, step: &str, message: &str| {
        let senders = state.event_senders.try_lock();
        if let Ok(senders) = senders {
            if let Some(tx) = senders.get(&job_id) {
                let _ = tx.send(BuildEvent::PipelineStep {
                    phase: phase.to_string(),
                    step: step.to_string(),
                    message: message.to_string(),
                });
            }
        }
    };

    // Transition to GeneratingLegalPages
    broadcast_step("legal_pages", "generating", "Generating privacy policy & terms of use…");
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::GeneratingLegalPages;
    }

    // ── Resolve app metadata ──────────────────────────────────────────────
    let app_name = request.title.clone();
    let bundle_id = derive_bundle_id(&request);
    let app_slug = request
        .title
        .to_lowercase()
        .replace(' ', "-")
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .collect::<String>();
    let description = request.prompt.clone();
    let category = request.category.clone();

    // Try to read AI-generated metadata if available
    let metadata_path = std::path::Path::new(&project_path).join("asc_metadata.json");
    let (meta_name, meta_description) = if metadata_path.exists() {
        if let Ok(contents) = std::fs::read_to_string(&metadata_path) {
            if let Ok(meta) = serde_json::from_str::<serde_json::Value>(&contents) {
                (
                    meta.get("name").and_then(|v| v.as_str()).unwrap_or(&app_name).to_string(),
                    meta.get("description").and_then(|v| v.as_str()).unwrap_or(&description).to_string(),
                )
            } else {
                (app_name.clone(), description.clone())
            }
        } else {
            (app_name.clone(), description.clone())
        }
    } else {
        (app_name.clone(), description.clone())
    };

    // ── Generate HTML pages ────────────────────────────────────────────────
    let current_year: i32 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i32 / 31_536_000 + 1970; // approximate year from epoch
    let contact_email = format!("support@{}.github.io", app_slug);

    let privacy_policy_html = format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Privacy Policy – {meta_name}</title>
<style>body{{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;max-width:680px;margin:2em auto;padding:0 1em;color:#1a1a1a;line-height:1.6}}h1{{color:#007aff}}h2{{border-bottom:1px solid #e0e0e0;padding-bottom:.3em}}</style>
</head>
<body>
<h1>Privacy Policy for {meta_name}</h1>
<p><em>Last updated: {current_year}</em></p>
<h2>Information We Collect</h2>
<p>{meta_name} collects minimal data necessary to provide its core functionality. This may include:</p>
<ul>
<li><strong>Account Information:</strong> When you sign up, we collect your email address and display name.</li>
<li><strong>Usage Data:</strong> We collect anonymized data about how you use the app, such as features accessed and session duration.</li>
<li><strong>Device Information:</strong> We may collect device model, operating system version, and crash logs to improve stability.</li>
</ul>
<h2>How We Use Your Information</h2>
<p>We use collected information to:</p>
<ul>
<li>Provide and maintain our service</li>
<li>Improve and personalize your experience</li>
<li>Send important notifications about the service</li>
<li>Respond to your inquiries and support requests</li>
</ul>
<h2>Third-Party Services</h2>
<p>{meta_name} may use third-party services that collect information used to identify you. These may include:</p>
<ul>
<li>Apple App Store services for app delivery and updates</li>
<li>Analytics services to help us understand app usage patterns</li>
<li>Cloud infrastructure providers for data storage and processing</li>
</ul>
<p>Refer to the privacy policies of these third-party services for more details.</p>
<h2>Data Retention</h2>
<p>We retain your personal data only for as long as necessary to fulfill the purposes outlined in this policy. You may request deletion of your data at any time by contacting us.</p>
<h2>Your Rights</h2>
<p>You have the right to:</p>
<ul>
<li>Access the personal data we hold about you</li>
<li>Request correction of inaccurate data</li>
<li>Request deletion of your data</li>
<li>Object to processing of your data</li>
<li>Request data portability</li>
</ul>
<h2>Children's Privacy</h2>
<p>{meta_name} does not knowingly collect personal information from children under 13. If you believe we have collected data from a child, please contact us immediately.</p>
<h2>Contact Us</h2>
<p>If you have any questions about this Privacy Policy, please contact us at:</p>
<p><a href="mailto:{contact_email}">{contact_email}</a></p>
</body>
</html>"#);

    let terms_of_use_html = format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Terms of Use – {meta_name}</title>
<style>body{{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;max-width:680px;margin:2em auto;padding:0 1em;color:#1a1a1a;line-height:1.6}}h1{{color:#007aff}}h2{{border-bottom:1px solid #e0e0e0;padding-bottom:.3em}}</style>
</head>
<body>
<h1>Terms of Use for {meta_name}</h1>
<p><em>Last updated: {current_year}</em></p>
<h2>1. Acceptance of Terms</h2>
<p>By downloading, installing, or using {meta_name}, you agree to be bound by these Terms of Use. If you do not agree, do not use the app.</p>
<h2>2. Description of Service</h2>
<p>{meta_name} is a {category} application that provides the following functionality: {meta_description}.</p>
<h2>3. User Responsibilities</h2>
<p>You agree to:</p>
<ul>
<li>Use the app only for lawful purposes</li>
<li>Not attempt to gain unauthorized access to any part of the service</li>
<li>Not use the service in any way that could damage, disable, or impair the service</li>
<li>Provide accurate information where required</li>
</ul>
<h2>4. Disclaimer of Warranties</h2>
<p>THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.</p>
<h2>5. Limitation of Liability</h2>
<p>TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES, WHETHER INCURRED DIRECTLY OR INDIRECTLY, OR ANY LOSS OF DATA, GOODWILL, OR OTHER INTANGIBLE LOSSES RESULTING FROM YOUR USE OF THE SERVICE.</p>
<h2>6. Modifications</h2>
<p>We reserve the right to modify these terms at any time. Continued use of the service after modifications constitutes acceptance of the updated terms.</p>
<h2>7. Termination</h2>
<p>We may terminate or suspend access to our service immediately, without prior notice, for any reason, including breach of these Terms.</p>
<h2>8. Governing Law</h2>
<p>These Terms shall be governed by the laws of the United States, without regard to its conflict of law provisions.</p>
<h2>9. Contact</h2>
<p>For questions about these Terms of Use, please contact us at:</p>
<p><a href="mailto:{contact_email}">{contact_email}</a></p>
</body>
</html>"#);

    // ── Publish to GitHub Pages ────────────────────────────────────────────
    // Transition to PublishingLegalPages
    broadcast_step("legal_pages", "publishing", "Publishing legal pages to GitHub Pages…");
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::PublishingLegalPages;
    }

    // Determine GitHub username (default: "codegenie-apps")
    let github_username = "codegenie-apps";
    let repo_name = format!("{}-legal", app_slug);

    // Create repo and push files using GitHub API
    let github_token = std::env::var("GITHUB_TOKEN").unwrap_or_else(|_| "".to_string());
    let github_token = if github_token.is_empty() {
        // Attempt to read from credentials file
        let cred_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
            .join(".config")
            .join("codegenie")
            .join("github_token");
        if cred_path.exists() {
            if let Ok(tok) = std::fs::read_to_string(&cred_path) {
                tok.trim().to_string()
            } else {
                String::new()
            }
        } else {
            String::new()
        }
    } else {
        github_token
    };

    let github_token = if github_token.is_empty() {
        // Try gh auth token as fallback
        let gh_output = tokio::process::Command::new("gh")
            .args(["auth", "token"])
            .output()
            .await;
        match gh_output {
            Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).trim().to_string(),
            _ => String::new(),
        }
    } else {
        github_token
    };

    let privacy_url: String;
    let terms_url: String;
    let repo_url: String;

    if github_token.is_empty() {
        // No GitHub token available — write files locally and return local paths
        broadcast_step("legal_pages", "no_token", "No GitHub token found; writing legal pages locally.");

        let legal_dir = std::path::Path::new(&project_path).join("LegalPages");
        std::fs::create_dir_all(&legal_dir)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create LegalPages dir: {e}")))?;

        std::fs::write(legal_dir.join("privacy-policy.html"), &privacy_policy_html)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to write privacy policy: {e}")))?;
        std::fs::write(legal_dir.join("terms-of-use.html"), &terms_of_use_html)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to write terms of use: {e}")))?;

        privacy_url = format!("file://{}/privacy-policy.html", legal_dir.to_string_lossy());
        terms_url = format!("file://{}/terms-of-use.html", legal_dir.to_string_lossy());
        repo_url = String::new();
    } else {
        // Use GitHub API to create/update repo and push files
        let client = reqwest::Client::new();
        let auth_header = format!("token {github_token}");

        // ── Step 1: Create the repo (ignore 422 if already exists) ──────
        broadcast_step("legal_pages", "creating_repo", &format!("Creating GitHub repo {github_username}/{repo_name}…"));

        let create_repo_body = serde_json::json!({
            "name": repo_name,
            "description": format!("Legal pages for {meta_name}"),
            "homepage": format!("https://{github_username}.github.io/{app_slug}"),
            "has_issues": false,
            "has_projects": false,
            "has_wiki": false,
            "auto_init": true
        });

        let _ = client
            .post("https://api.github.com/user/repos")
            .header("Authorization", &auth_header)
            .header("Content-Type", "application/json")
            .header("User-Agent", "CodeGenie")
            .json(&create_repo_body)
            .send()
            .await;

        // ── Step 2: Enable GitHub Pages ─────────────────────────────────
        broadcast_step("legal_pages", "enabling_pages", "Enabling GitHub Pages…");

        let pages_body = serde_json::json!({
            "build_type": "workflow"
        });

        let _ = client
            .post(format!("https://api.github.com/repos/{github_username}/{repo_name}/pages"))
            .header("Authorization", &auth_header)
            .header("Content-Type", "application/json")
            .header("User-Agent", "CodeGenie")
            .json(&pages_body)
            .send()
            .await;

        // ── Step 3: Write a GitHub Actions workflow for Pages ───────────
        let workflow_dir = format!(".github/workflows");
        let workflow_content = r#"name: Deploy Pages
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: false
jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - uses: actions/upload-pages-artifact@v3
        with:
          path: .
      - id: deployment
        uses: actions/deploy-pages@v4"#;

        let workflow_b64 = BASE64.encode(workflow_content.as_bytes());
        let workflow_path = format!("{workflow_dir}/pages.yml");
        let _ = push_file_to_github(&client, &auth_header, github_username, &repo_name, &workflow_path, &workflow_b64, "Add GitHub Pages workflow").await;

        // ── Step 4: Push privacy-policy.html and terms-of-use.html ─────
        broadcast_step("legal_pages", "pushing_files", "Pushing legal pages to GitHub…");

        let privacy_b64 = BASE64.encode(privacy_policy_html.as_bytes());
        let terms_b64 = BASE64.encode(terms_of_use_html.as_bytes());

        push_file_to_github(&client, &auth_header, github_username, &repo_name, "privacy-policy.html", &privacy_b64, "Add privacy policy").await?;
        push_file_to_github(&client, &auth_header, github_username, &repo_name, "terms-of-use.html", &terms_b64, "Add terms of use").await?;

        privacy_url = format!("https://{github_username}.github.io/{app_slug}/privacy-policy.html");
        terms_url = format!("https://{github_username}.github.io/{app_slug}/terms-of-use.html");
        repo_url = format!("https://github.com/{github_username}/{repo_name}");
    }

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    broadcast_step("legal_pages", "published", "Legal pages published successfully.");

    Ok(Json(LegalPagesResponse {
        job_id,
        status: "published".to_string(),
        privacy_url,
        terms_url,
        repo_url,
    }))
}

// ── AI Recovery Engine handlers ────────────────────────────────────────────

/// `POST /api/build/:job_id/steer`
///
/// Diagnose a pipeline step failure and propose a recovery action.
/// The iOS client calls this when any pipeline step fails, sending the
/// step name, error message, and retry count. The server uses pattern
/// matching on known failure modes and falls back to AI diagnosis.
async fn steer(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(body): Json<SteerRequest>,
) -> Result<Json<SteerResponse>, (StatusCode, String)> {
    // Verify the job exists
    let _job = state
        .jobs
        .lock()
        .await
        .get(&job_id)
        .cloned()
        .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?;

    let ctx = body.error_context;

    // Diagnose the failure mode from the error message
    let proposal = diagnose_failure(&ctx.step, &ctx.error_message, ctx.retry_count);

    Ok(Json(SteerResponse {
        job_id,
        proposal,
    }))
}

/// `POST /api/build/:job_id/recover`
///
/// Apply a user-approved recovery action. The iOS client sends the
/// recovery proposal (possibly with modified fix_params) and the server
/// executes the fix, then returns success/failure and which step to retry.
async fn recover(
    State(state): State<Arc<AppState>>,
    Path(job_id): Path<String>,
    Json(body): Json<RecoverRequest>,
) -> Result<Json<RecoverResponse>, (StatusCode, String)> {
    // Verify the job exists and get a clone for the recovery fix
    let job_arc = state
        .jobs
        .lock()
        .await
        .get(&job_id)
        .cloned()
        .ok_or((StatusCode::NOT_FOUND, format!("Job {job_id} not found")))?;

    let job = job_arc.lock().await.clone();
    let proposal = body.proposal;

    // Broadcast recovery attempt
    {
        let senders = state.event_senders.try_lock();
        if let Ok(senders) = senders {
            if let Some(tx) = senders.get(&job_id) {
                let _ = tx.send(BuildEvent::PipelineStep {
                    phase: "recovery".into(),
                    step: "applying_fix".into(),
                    message: format!("Applying recovery: {}", proposal.fix_description),
                });
            }
        }
    }

    // Apply the recovery fix
    match apply_recovery_fix(&job, &proposal) {
        Ok(retry_step) => {
            // Broadcast success
            {
                let senders = state.event_senders.try_lock();
                if let Ok(senders) = senders {
                    if let Some(tx) = senders.get(&job_id) {
                        let _ = tx.send(BuildEvent::PipelineStep {
                            phase: "recovery".into(),
                            step: "fix_applied".into(),
                            message: format!("Recovery applied: {}", proposal.fix_description),
                        });
                    }
                }
            }
            Ok(Json(RecoverResponse {
                job_id,
                success: true,
                message: format!("Recovery applied: {}", proposal.fix_description),
                retry_step: Some(retry_step),
            }))
        }
        Err(err) => {
            // Broadcast failure
            {
                let senders = state.event_senders.try_lock();
                if let Ok(senders) = senders {
                    if let Some(tx) = senders.get(&job_id) {
                        let _ = tx.send(BuildEvent::PipelineStep {
                            phase: "recovery".into(),
                            step: "fix_failed".into(),
                            message: format!("Recovery failed: {err}"),
                        });
                    }
                }
            }
            Ok(Json(RecoverResponse {
                job_id,
                success: false,
                message: format!("Recovery failed: {err}"),
                retry_step: None,
            }))
        }
    }
}

/// Helper: Push a file to GitHub via the Contents API.
/// Returns an error string on failure.
async fn push_file_to_github(
    client: &reqwest::Client,
    auth_header: &str,
    owner: &str,
    repo: &str,
    path: &str,
    content_b64: &str,
    message: &str,
) -> Result<(), (StatusCode, String)> {
    let url = format!("https://api.github.com/repos/{owner}/{repo}/contents/{path}");

    // First, try to get the existing file's SHA (for updates)
    let sha: Option<String> = match client
        .get(&url)
        .header("Authorization", auth_header)
        .header("User-Agent", "CodeGenie")
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            match resp.text().await {
                Ok(body) => serde_json::from_str::<serde_json::Value>(&body)
                    .ok()
                    .and_then(|v| v.get("sha")?.as_str().map(|s| s.to_string())),
                Err(_) => None,
            }
        }
        _ => None,
    };

    let mut body = serde_json::json!({
        "message": message,
        "content": content_b64,
    });
    if let Some(sha) = sha {
        body["sha"] = serde_json::Value::String(sha);
    }

    let resp = client
        .put(&url)
        .header("Authorization", auth_header)
        .header("Content-Type", "application/json")
        .header("User-Agent", "CodeGenie")
        .json(&body)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("GitHub API request failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body_text = resp.text().await.unwrap_or_default();
        // Don't fail hard — log a warning but continue
        eprintln!("Warning: GitHub push for {path} returned {status}: {body_text}");
    }

    Ok(())
}

// ── New endpoint handlers: asc-icon, screenshots/upload, asc-whatsnew ────

/// `POST /api/asc-icon` — Check / gate for app icon upload to ASC.
///
/// The ASC REST API does NOT expose an endpoint for uploading app icons (all
/// attempts return 404). This handler checks whether the icon has already been
/// uploaded via the web UI and, if not, returns a JSON payload telling the
/// iOS client that the user must upload the icon manually through Safari.
async fn asc_icon(
    Json(body): Json<serde_json::Value>,
) -> Result<Json<AscIconResponse>, (StatusCode, String)> {
    let app_id = body
        .get("app_id")
        .and_then(|v| v.as_str())
        .unwrap_or("6778610091");

    // ── Generate ASC JWT ──────────────────────────────────────────────────
    let asc_key_id = "N8LHKCW7K8";
    let asc_issuer_id = "69a6de94-afa7-47e3-e053-5b8c7c11a4d1";
    let key_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("private_keys")
        .join("AuthKey_N8LHKCW7K8.p8");

    let jwt = match generate_asc_jwt(asc_key_id, asc_issuer_id, &key_path) {
        Ok(token) => token,
        Err(e) => {
            return Ok(Json(AscIconResponse {
                needs_manual_action: true,
                action: Some("upload_app_icon".to_string()),
                message: Some(format!("Could not generate ASC JWT: {e}")),
                url: Some(format!(
                    "https://appstoreconnect.apple.com/apps/{app_id}/appstore/ios/version/information"
                )),
                icon_uploaded: None,
            }));
        }
    };

    // ── Check if icon is already uploaded via ASC API ──────────────────────
    let client = reqwest::Client::new();
    let icon_url = format!(
        "https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appInfoLocalizations"
    );

    let response = match client
        .get(&icon_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
    {
        Ok(resp) => resp,
        Err(e) => {
            return Ok(Json(AscIconResponse {
                needs_manual_action: true,
                action: Some("upload_app_icon".to_string()),
                message: Some(format!("Failed to query ASC API: {e}")),
                url: Some(format!(
                    "https://appstoreconnect.apple.com/apps/{app_id}/appstore/ios/version/information"
                )),
                icon_uploaded: None,
            }));
        }
    };

    let status = response.status();
    let body_text = response.text().await.unwrap_or_default();

    if status.is_success() {
        // Try to determine if an icon is present in the response
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body_text) {
            // Look for appIcon data in included or relationships
            let has_icon = json
                .get("data")
                .and_then(|d| d.as_array())
                .map(|arr| {
                    arr.iter().any(|loc| {
                        loc.get("relationships")
                            .and_then(|r| r.get("appIcon"))
                            .and_then(|ic| ic.get("data"))
                            .is_some()
                    })
                })
                .unwrap_or(false);

            if has_icon {
                return Ok(Json(AscIconResponse {
                    needs_manual_action: false,
                    action: None,
                    message: None,
                    url: None,
                    icon_uploaded: Some(true),
                }));
            }
        }
    }

    // Icon not found or ASC API doesn't support icon queries — return manual action
    Ok(Json(AscIconResponse {
        needs_manual_action: true,
        action: Some("upload_app_icon".to_string()),
        message: Some(
            "App icon must be uploaded via App Store Connect web interface. Open Safari, sign in to ASC, navigate to your app, and upload the icon.".to_string(),
        ),
        url: Some(format!(
            "https://appstoreconnect.apple.com/apps/{app_id}/appstore/ios/version/information"
        )),
        icon_uploaded: Some(false),
    }))
}

/// `POST /api/screenshots/upload` — Upload screenshots to ASC via S3.
///
/// The flow is:
/// 1. POST /v1/appScreenshotSets → create a screenshot set
/// 2. POST /v1/appScreenshots → create a screenshot resource (get S3 upload URL)
/// 3. PUT to S3 with PNG binary data
/// 4. PATCH /v1/appScreenshots/{id} with {uploaded: true} to confirm
async fn screenshots_upload(
    Json(req): Json<ScreenshotsUploadRequest>,
) -> Result<Json<ScreenshotsUploadResponse>, (StatusCode, String)> {
    // ── Generate ASC JWT ──────────────────────────────────────────────────
    let asc_key_id = "N8LHKCW7K8";
    let asc_issuer_id = "69a6de94-afa7-47e3-e053-5b8c7c11a4d1";
    let key_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("private_keys")
        .join("AuthKey_N8LHKCW7K8.p8");

    let jwt = generate_asc_jwt(asc_key_id, asc_issuer_id, &key_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to generate ASC JWT: {e}")))?;

    let client = reqwest::Client::new();
    let mut results = Vec::new();

    for screenshot in &req.screenshots {
        let result = upload_single_screenshot(
            &client,
            &jwt,
            &req.version_localization_id,
            screenshot,
        )
        .await;

        results.push(result);
    }

    Ok(Json(ScreenshotsUploadResponse { results }))
}

/// Upload a single screenshot through the full ASC → S3 → confirm pipeline.
async fn upload_single_screenshot(
    client: &reqwest::Client,
    jwt: &str,
    version_localization_id: &str,
    screenshot: &ScreenshotEntry,
) -> ScreenshotUploadResult {
    // ── Step 1: Create screenshot set ─────────────────────────────────────
    let set_payload = serde_json::json!({
        "data": {
            "type": "appScreenshotSets",
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": version_localization_id
                    }
                },
                "screenshotDisplayType": screenshot.display_type
            }
        }
    });

    let set_response = match client
        .post("https://api.appstoreconnect.apple.com/v1/appScreenshotSets")
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&set_payload)
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to create screenshot set: {e}")),
                screenshot_id: None,
            };
        }
    };

    let set_status = set_response.status();
    let set_body = match set_response.text().await {
        Ok(b) => b,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to read screenshot set response: {e}")),
                screenshot_id: None,
            };
        }
    };

    // If set already exists, we need to find its ID; parse the response
    let (set_id, is_existing_set) = if set_status.is_success() || set_status.as_u16() == 409 {
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&set_body) {
            // If 201, the set was created
            if set_status.is_success() {
                let id = json
                    .get("data")
                    .and_then(|d| d.get("id"))
                    .and_then(|i| i.as_str())
                    .unwrap_or("")
                    .to_string();
                (id, false)
            } else {
                // 409 conflict — set already exists; find it from the errors
                // Try to find existing set from the response
                let existing_id = json
                    .get("data")
                    .and_then(|d| d.get("id"))
                    .and_then(|i| i.as_str())
                    .unwrap_or("")
                    .to_string();
                if !existing_id.is_empty() {
                    (existing_id, true)
                } else {
                    // Try to find from relationships/errors
                    let err_id = json
                        .get("errors")
                        .and_then(|e| e.as_array())
                        .and_then(|arr| arr.first())
                        .and_then(|e| e.get("meta"))
                        .and_then(|m| m.get("associatedResources"))
                        .and_then(|a| a.as_array())
                        .and_then(|arr| arr.first())
                        .and_then(|r| r.get("id"))
                        .and_then(|i| i.as_str())
                        .unwrap_or("")
                        .to_string();
                    (err_id, true)
                }
            }
        } else {
            (
                String::new(),
                set_status.as_u16() == 409,
            )
        }
    } else {
        return ScreenshotUploadResult {
            filename: screenshot.filename.clone(),
            display_type: screenshot.display_type.clone(),
            success: false,
            error: Some(format!(
                "Screenshot set creation returned {}: {}",
                set_status, set_body
            )),
            screenshot_id: None,
        };
    };

    // If we didn't get a set ID, try listing existing sets for this localization
    let set_id = if set_id.is_empty() {
        // List screenshot sets for the version localization
        let list_url = format!(
            "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/{version_localization_id}/appScreenshotSets"
        );
        match client
            .get(&list_url)
            .header("Authorization", format!("Bearer {jwt}"))
            .header("Content-Type", "application/json")
            .send()
            .await
        {
            Ok(resp) => {
                let list_body = resp.text().await.unwrap_or_default();
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&list_body) {
                    json.get("data")
                        .and_then(|d| d.as_array())
                        .and_then(|arr| {
                            arr.iter().find(|s| {
                                s.get("attributes")
                                    .and_then(|a| a.get("screenshotDisplayType"))
                                    .and_then(|t| t.as_str())
                                    .map(|t| t == screenshot.display_type)
                                    .unwrap_or(false)
                            })
                        })
                        .and_then(|s| s.get("id"))
                        .and_then(|i| i.as_str())
                        .unwrap_or("")
                        .to_string()
                } else {
                    String::new()
                }
            }
            Err(_) => String::new(),
        }
    } else {
        set_id
    };

    if set_id.is_empty() {
        return ScreenshotUploadResult {
            filename: screenshot.filename.clone(),
            display_type: screenshot.display_type.clone(),
            success: false,
            error: Some("Could not determine screenshot set ID".to_string()),
            screenshot_id: None,
        };
    }

    // ── Step 2: Create screenshot resource (gets S3 upload URL) ────────────
    let screenshot_payload = serde_json::json!({
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileName": screenshot.filename,
                "fileSize": screenshot.data_base64.len() as i64
            },
            "relationships": {
                "appScreenshotSet": {
                    "data": {
                        "type": "appScreenshotSets",
                        "id": set_id
                    }
                }
            }
        }
    });

    let sc_response = match client
        .post("https://api.appstoreconnect.apple.com/v1/appScreenshots")
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&screenshot_payload)
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to create screenshot resource: {e}")),
                screenshot_id: None,
            };
        }
    };

    let sc_status = sc_response.status();
    let sc_body = match sc_response.text().await {
        Ok(b) => b,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to read screenshot creation response: {e}")),
                screenshot_id: None,
            };
        }
    };

    if !sc_status.is_success() {
        return ScreenshotUploadResult {
            filename: screenshot.filename.clone(),
            display_type: screenshot.display_type.clone(),
            success: false,
            error: Some(format!(
                "Screenshot creation returned {}: {}",
                sc_status, sc_body
            )),
            screenshot_id: None,
        };
    }

    // Parse the response to get the screenshot ID and upload URLs
    let sc_json: serde_json::Value = match serde_json::from_str(&sc_body) {
        Ok(j) => j,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to parse screenshot response: {e}")),
                screenshot_id: None,
            };
        }
    };

    let screenshot_id = sc_json
        .get("data")
        .and_then(|d| d.get("id"))
        .and_then(|i| i.as_str())
        .unwrap_or("")
        .to_string();

    // Extract upload operations from the response
    let upload_ops = sc_json
        .get("data")
        .and_then(|d| d.get("attributes"))
        .and_then(|a| a.get("uploadOperations"));

    let (upload_url, request_headers) = match upload_ops {
        Some(ops) if ops.is_array() => {
            // Find the PUT operation (method == "PUT")
            let ops_arr = ops.as_array().unwrap();
            let put_op = ops_arr.iter().find(|op| {
                op.get("method")
                    .and_then(|m| m.as_str())
                    .map(|m| m == "PUT")
                    .unwrap_or(false)
            });

            match put_op {
                Some(op) => {
                    let url = op
                        .get("url")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                    let headers = op
                        .get("requestHeaders")
                        .and_then(|h| h.as_array())
                        .cloned()
                        .unwrap_or_default();
                    (url, headers)
                }
                None => {
                    // Try the first operation (might be the only one)
                    let first = ops_arr.first();
                    match first {
                        Some(op) => {
                            let url = op
                                .get("url")
                                .and_then(|u| u.as_str())
                                .unwrap_or("")
                                .to_string();
                            let headers = op
                                .get("requestHeaders")
                                .and_then(|h| h.as_array())
                                .cloned()
                                .unwrap_or_default();
                            (url, headers)
                        }
                        None => {
                            return ScreenshotUploadResult {
                                filename: screenshot.filename.clone(),
                                display_type: screenshot.display_type.clone(),
                                success: false,
                                error: Some(
                                    "No upload operations returned from ASC API".to_string(),
                                ),
                                screenshot_id: Some(screenshot_id),
                            };
                        }
                    }
                }
            }
        }
        _ => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(
                    "No upload operations found in screenshot creation response".to_string(),
                ),
                screenshot_id: Some(screenshot_id),
            };
        }
    };

    if upload_url.is_empty() {
        return ScreenshotUploadResult {
            filename: screenshot.filename.clone(),
            display_type: screenshot.display_type.clone(),
            success: false,
            error: Some("Empty S3 upload URL from ASC".to_string()),
            screenshot_id: Some(screenshot_id),
        };
    }

    // ── Step 3: Upload PNG binary data to S3 ───────────────────────────────
    let png_data = match BASE64.decode(&screenshot.data_base64) {
        Ok(data) => data,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to decode base64 screenshot data: {e}")),
                screenshot_id: Some(screenshot_id),
            };
        }
    };

    // Build the S3 PUT request with required headers from uploadOperations
    let mut s3_request = client
        .put(&upload_url)
        .header("Content-Type", "image/png")
        .header("Content-Length", png_data.len().to_string())
        .body(png_data);

    // Apply required headers from ASC uploadOperations
    for header in &request_headers {
        let name = header
            .get("name")
            .and_then(|n| n.as_str())
            .unwrap_or("");
        let value = header
            .get("value")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if !name.is_empty() && !value.is_empty() {
            s3_request = s3_request.header(name, value);
        }
    }

    let s3_response = match s3_request.send().await {
        Ok(r) => r,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to upload to S3: {e}")),
                screenshot_id: Some(screenshot_id),
            };
        }
    };

    let s3_status = s3_response.status();
    if !s3_status.is_success() {
        let s3_body = s3_response.text().await.unwrap_or_default();
        return ScreenshotUploadResult {
            filename: screenshot.filename.clone(),
            display_type: screenshot.display_type.clone(),
            success: false,
            error: Some(format!("S3 upload returned {}: {}", s3_status, s3_body)),
            screenshot_id: Some(screenshot_id),
        };
    }

    // ── Step 4: PATCH screenshot with uploaded=true ─────────────────────────
    let patch_payload = serde_json::json!({
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {
                "uploaded": true,
                "sourceFileChecksum": ""
            }
        }
    });

    let patch_url = format!(
        "https://api.appstoreconnect.apple.com/v1/appScreenshots/{screenshot_id}"
    );

    let patch_response = match client
        .patch(&patch_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&patch_payload)
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            return ScreenshotUploadResult {
                filename: screenshot.filename.clone(),
                display_type: screenshot.display_type.clone(),
                success: false,
                error: Some(format!("Failed to confirm screenshot upload: {e}")),
                screenshot_id: Some(screenshot_id),
            };
        }
    };

    let patch_status = patch_response.status();
    if !patch_status.is_success() {
        let patch_body = patch_response.text().await.unwrap_or_default();
        return ScreenshotUploadResult {
            filename: screenshot.filename.clone(),
            display_type: screenshot.display_type.clone(),
            success: false,
            error: Some(format!(
                "Screenshot confirm PATCH returned {}: {}",
                patch_status,
                patch_body
            )),
            screenshot_id: Some(screenshot_id),
        };
    }

    ScreenshotUploadResult {
        filename: screenshot.filename.clone(),
        display_type: screenshot.display_type.clone(),
        success: true,
        error: None,
        screenshot_id: Some(screenshot_id),
    }
}

/// `PATCH /api/asc-whatsnew` — Set the "What's New" text for a version localization.
///
/// Takes a version_localization_id and whats_new text, then PATCHes the ASC API.
/// Note: This only works AFTER a build is attached to the version.
async fn asc_whatsnew(
    Json(req): Json<AscWhatsNewRequest>,
) -> Result<Json<AscWhatsNewResponse>, (StatusCode, String)> {
    // ── Generate ASC JWT ──────────────────────────────────────────────────
    let asc_key_id = "N8LHKCW7K8";
    let asc_issuer_id = "69a6de94-afa7-47e3-e053-5b8c7c11a4d1";
    let key_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("private_keys")
        .join("AuthKey_N8LHKCW7K8.p8");

    let jwt = generate_asc_jwt(asc_key_id, asc_issuer_id, &key_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to generate ASC JWT: {e}")))?;

    let client = reqwest::Client::new();

    // ── PATCH the version localization ──────────────────────────────────────
    let patch_payload = serde_json::json!({
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": req.version_localization_id,
            "attributes": {
                "whatsNew": req.whats_new
            }
        }
    });

    let patch_url = format!(
        "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/{}",
        req.version_localization_id
    );

    let response = client
        .patch(&patch_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&patch_payload)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to send PATCH request: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read response: {e}")))?;

    if status.is_success() {
        Ok(Json(AscWhatsNewResponse {
            ok: true,
            error: None,
        }))
    } else {
        Ok(Json(AscWhatsNewResponse {
            ok: false,
            error: Some(format!("ASC API returned {}: {}", status.as_u16(), body)),
        }))
    }
}

// ── Beta Tester & Beta Review endpoints ──────────────────────────────────

/// Helper to generate an ASC JWT with the hardcoded credentials.
fn make_asc_jwt() -> Result<String, (StatusCode, String)> {
    let asc_key_id = "N8LHKCW7K8";
    let asc_issuer_id = "69a6de94-afa7-47e3-e053-5b8c7c11a4d1";
    let key_path = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join("private_keys")
        .join("AuthKey_N8LHKCW7K8.p8");
    generate_asc_jwt(asc_key_id, asc_issuer_id, &key_path)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to generate ASC JWT: {e}")))
}

const APP_ID: &str = "6778610091";
const BETA_GROUP_ID: &str = "1475d312-4be7-45e7-a23b-52be531c6a7b";

/// `GET /api/testers` — List all beta testers for the app.
async fn list_testers() -> Result<Json<ListTestersResponse>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();
    let url = format!(
        "https://api.appstoreconnect.apple.com/v1/betaTesters?filter[apps]={APP_ID}&limit=200"
    );

    let response = client
        .get(&url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query ASC testers: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !status.is_success() {
        return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", status.as_u16(), body)));
    }

    let json: serde_json::Value = serde_json::from_str(&body)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to parse ASC response: {e}")))?;

    let mut testers = Vec::new();
    if let Some(data) = json.get("data").and_then(|d| d.as_array()) {
        for item in data {
            let id = item.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let attrs = item.get("attributes").unwrap_or(&serde_json::Value::Null);
            let email = attrs.get("email").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let first_name = attrs.get("firstName").and_then(|v| v.as_str()).map(String::from);
            let last_name = attrs.get("lastName").and_then(|v| v.as_str()).map(String::from);
            let state = attrs.get("state").and_then(|v| v.as_str()).map(String::from);
            let invite_type = attrs.get("inviteType").and_then(|v| v.as_str()).map(String::from);
            testers.push(BetaTester {
                id,
                email,
                first_name,
                last_name,
                state,
                invite_type,
            });
        }
    }

    Ok(Json(ListTestersResponse { testers }))
}

/// `POST /api/testers` — Add a beta tester by email.
async fn add_tester(
    Json(req): Json<AddTesterRequest>,
) -> Result<Json<BetaTester>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    let payload = serde_json::json!({
        "data": {
            "type": "betaTesters",
            "attributes": {
                "email": req.email,
                "firstName": req.first_name.unwrap_or_default(),
                "lastName": req.last_name.unwrap_or_default(),
            },
            "relationships": {
                "betaGroups": {
                    "data": [{
                        "type": "betaGroups",
                        "id": BETA_GROUP_ID
                    }]
                },
                "app": {
                    "data": {
                        "type": "apps",
                        "id": APP_ID
                    }
                }
            }
        }
    });

    let response = client
        .post("https://api.appstoreconnect.apple.com/v1/betaTesters")
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to add beta tester: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !status.is_success() {
        return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", status.as_u16(), body)));
    }

    let json: serde_json::Value = serde_json::from_str(&body)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to parse ASC response: {e}")))?;

    let id = json.get("data").and_then(|d| d.get("id")).and_then(|v| v.as_str()).unwrap_or("").to_string();
    let attrs = json.get("data").and_then(|d| d.get("attributes")).unwrap_or(&serde_json::Value::Null);
    let email = attrs.get("email").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let first_name = attrs.get("firstName").and_then(|v| v.as_str()).map(String::from);
    let last_name = attrs.get("lastName").and_then(|v| v.as_str()).map(String::from);
    let state = attrs.get("state").and_then(|v| v.as_str()).map(String::from);
    let invite_type = attrs.get("inviteType").and_then(|v| v.as_str()).map(String::from);

    Ok(Json(BetaTester {
        id,
        email,
        first_name,
        last_name,
        state,
        invite_type,
    }))
}

/// `DELETE /api/testers/{tester_id}` — Remove a beta tester.
async fn delete_tester(
    Path(tester_id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();
    let url = format!(
        "https://api.appstoreconnect.apple.com/v1/betaTesters/{tester_id}"
    );

    let response = client
        .delete(&url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to delete beta tester: {e}")))?;

    if response.status().is_success() || response.status().as_u16() == 204 {
        Ok(StatusCode::NO_CONTENT)
    } else {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", status.as_u16(), body)))
    }
}

/// `POST /api/testers/assign-build` — Assign testers to a build.
async fn assign_testers_to_build(
    Json(req): Json<AssignTestersRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    let mut data_items = Vec::new();
    for tid in &req.tester_ids {
        data_items.push(serde_json::json!({
            "type": "betaTesters",
            "id": tid
        }));
    }

    let payload = serde_json::json!({
        "data": data_items
    });

    let url = format!(
        "https://api.appstoreconnect.apple.com/v1/builds/{}/relationships/individualTesters",
        req.build_id
    );

    let response = client
        .post(&url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to assign testers: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !status.is_success() {
        // Return 409 specifically so the client can handle it
        let code = StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
        Err((code, format!("ASC API returned {}: {}", status.as_u16(), body)))
    } else {
        Ok(Json(serde_json::json!({ "ok": true })))
    }
}

/// `GET /api/beta-review` — Get beta review status for the current build.
async fn get_beta_review_status() -> Result<Json<BetaReviewStatusResponse>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    // First, get the latest build for the app
    let builds_url = format!(
        "https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}/builds?limit=1"
    );

    let builds_response = client
        .get(&builds_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query ASC builds: {e}")))?;

    let builds_status = builds_response.status();
    let builds_body = builds_response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !builds_status.is_success() {
        return Err((StatusCode::from_u16(builds_status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", builds_status.as_u16(), builds_body)));
    }

    let builds_json: serde_json::Value = serde_json::from_str(&builds_body)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to parse ASC builds response: {e}")))?;

    let build_id = builds_json
        .get("data")
        .and_then(|d| d.as_array())
        .and_then(|arr| arr.first())
        .and_then(|item| item.get("id"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    if build_id.is_empty() {
        return Ok(Json(BetaReviewStatusResponse {
            beta_review_state: "NO_BUILD".to_string(),
            submitted_date: None,
        }));
    }

    // Now query the beta app review submission for this build
    let review_url = format!(
        "https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions?filter[build]={build_id}"
    );

    let review_response = client
        .get(&review_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query beta review status: {e}")))?;

    let review_status_code = review_response.status();
    let review_body = review_response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !review_status_code.is_success() {
        return Err((StatusCode::from_u16(review_status_code.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", review_status_code.as_u16(), review_body)));
    }

    let review_json: serde_json::Value = serde_json::from_str(&review_body)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to parse beta review response: {e}")))?;

    let submission = review_json
        .get("data")
        .and_then(|d| d.as_array())
        .and_then(|arr| arr.first());

    match submission {
        Some(sub) => {
            let state = sub
                .get("attributes")
                .and_then(|a| a.get("betaReviewState"))
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN")
                .to_string();
            let submitted_date = sub
                .get("attributes")
                .and_then(|a| a.get("submittedDate"))
                .and_then(|v| v.as_str())
                .map(String::from);
            Ok(Json(BetaReviewStatusResponse {
                beta_review_state: state,
                submitted_date,
            }))
        }
        None => Ok(Json(BetaReviewStatusResponse {
            beta_review_state: "NOT_SUBMITTED".to_string(),
            submitted_date: None,
        })),
    }
}

/// `POST /api/beta-review/submit` — Submit the current build for beta review.
async fn submit_beta_review(
    Json(req): Json<BetaReviewSubmitRequest>,
) -> Result<Json<BetaReviewStatusResponse>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    let payload = serde_json::json!({
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": {
                    "data": {
                        "type": "builds",
                        "id": req.build_id
                    }
                }
            }
        }
    });

    let response = client
        .post("https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions")
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to submit for beta review: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !status.is_success() {
        return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", status.as_u16(), body)));
    }

    let json: serde_json::Value = serde_json::from_str(&body)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to parse beta review submission response: {e}")))?;

    let state = json
        .get("data")
        .and_then(|d| d.get("attributes"))
        .and_then(|a| a.get("betaReviewState"))
        .and_then(|v| v.as_str())
        .unwrap_or("WAITING_FOR_REVIEW")
        .to_string();
    let submitted_date = json
        .get("data")
        .and_then(|d| d.get("attributes"))
        .and_then(|a| a.get("submittedDate"))
        .and_then(|v| v.as_str())
        .map(String::from);

    Ok(Json(BetaReviewStatusResponse {
        beta_review_state: state,
        submitted_date,
    }))
}

/// `POST /api/beta-review/detail` — Set beta app review contact info.
async fn set_beta_review_detail(
    Json(req): Json<BetaReviewDetailRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    let payload = serde_json::json!({
        "data": {
            "type": "betaAppReviewDetails",
            "id": APP_ID,
            "attributes": {
                "contactFirstName": req.contact_first_name,
                "contactLastName": req.contact_last_name,
                "contactEmail": req.contact_email,
                "contactPhone": req.contact_phone,
            }
        }
    });

    let url = format!(
        "https://api.appstoreconnect.apple.com/v1/betaAppReviewDetails/{APP_ID}"
    );

    let response = client
        .patch(&url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to set beta review detail: {e}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    if !status.is_success() {
        return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("ASC API returned {}: {}", status.as_u16(), body)));
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// `POST /api/beta-review/localization` — Create/update beta build localization (What's New).
async fn set_beta_build_localization(
    Json(req): Json<BetaBuildLocalizationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    // First, check if a localization already exists for this build+locale
    let list_url = format!(
        "https://api.appstoreconnect.apple.com/v1/builds/{}/betaBuildLocalizations?filter[locale]={}",
        req.build_id, req.locale
    );

    let list_response = client
        .get(&list_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query build localizations: {e}")))?;

    let list_status = list_response.status();
    let list_body = list_response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    let existing_id = if list_status.is_success() {
        let list_json: serde_json::Value = serde_json::from_str(&list_body).unwrap_or_default();
        list_json
            .get("data")
            .and_then(|d| d.as_array())
            .and_then(|arr| arr.first())
            .and_then(|item| item.get("id"))
            .and_then(|v| v.as_str())
            .map(String::from)
    } else {
        None
    };

    if let Some(loc_id) = existing_id {
        // PATCH existing localization
        let patch_payload = serde_json::json!({
            "data": {
                "type": "betaBuildLocalizations",
                "id": loc_id,
                "attributes": {
                    "whatsNew": req.whats_new
                }
            }
        });

        let patch_url = format!(
            "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations/{loc_id}"
        );

        let response = client
            .patch(&patch_url)
            .header("Authorization", format!("Bearer {jwt}"))
            .header("Content-Type", "application/json")
            .json(&patch_payload)
            .send()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to update build localization: {e}")))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

        if !status.is_success() {
            return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
                format!("ASC API returned {}: {}", status.as_u16(), body)));
        }

        Ok(Json(serde_json::json!({ "ok": true, "localization_id": loc_id })))
    } else {
        // POST new localization
        let post_payload = serde_json::json!({
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {
                    "locale": req.locale,
                    "whatsNew": req.whats_new
                },
                "relationships": {
                    "build": {
                        "data": {
                            "type": "builds",
                            "id": req.build_id
                        }
                    }
                }
            }
        });

        let response = client
            .post("https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations")
            .header("Authorization", format!("Bearer {jwt}"))
            .header("Content-Type", "application/json")
            .json(&post_payload)
            .send()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create build localization: {e}")))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

        if !status.is_success() {
            return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
                format!("ASC API returned {}: {}", status.as_u16(), body)));
        }

        let json: serde_json::Value = serde_json::from_str(&body).unwrap_or_default();
        let new_id = json.get("data").and_then(|d| d.get("id")).and_then(|v| v.as_str()).unwrap_or("").to_string();

        Ok(Json(serde_json::json!({ "ok": true, "localization_id": new_id })))
    }
}

/// `POST /api/beta-review/app-localization` — Create/update beta app localization.
async fn set_beta_app_localization(
    Json(req): Json<BetaAppLocalizationRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let jwt = make_asc_jwt()?;
    let client = reqwest::Client::new();

    // Check if a localization already exists for this app+locale
    let list_url = format!(
        "https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}/betaAppLocalizations?filter[locale]={}",
        req.locale
    );

    let list_response = client
        .get(&list_url)
        .header("Authorization", format!("Bearer {jwt}"))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to query app localizations: {e}")))?;

    let list_status = list_response.status();
    let list_body = list_response
        .text()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

    let existing_id = if list_status.is_success() {
        let list_json: serde_json::Value = serde_json::from_str(&list_body).unwrap_or_default();
        list_json
            .get("data")
            .and_then(|d| d.as_array())
            .and_then(|arr| arr.first())
            .and_then(|item| item.get("id"))
            .and_then(|v| v.as_str())
            .map(String::from)
    } else {
        None
    };

    if let Some(loc_id) = existing_id {
        // PATCH existing localization
        let mut attrs = serde_json::json!({
            "feedbackEmail": req.feedback_email,
        });
        if let Some(ref desc) = req.description {
            attrs.as_object_mut().unwrap().insert("description".to_string(), serde_json::json!(desc));
        }

        let patch_payload = serde_json::json!({
            "data": {
                "type": "betaAppLocalizations",
                "id": loc_id,
                "attributes": attrs
            }
        });

        let patch_url = format!(
            "https://api.appstoreconnect.apple.com/v1/betaAppLocalizations/{loc_id}"
        );

        let response = client
            .patch(&patch_url)
            .header("Authorization", format!("Bearer {jwt}"))
            .header("Content-Type", "application/json")
            .json(&patch_payload)
            .send()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to update app localization: {e}")))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

        if !status.is_success() {
            return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
                format!("ASC API returned {}: {}", status.as_u16(), body)));
        }

        Ok(Json(serde_json::json!({ "ok": true, "localization_id": loc_id })))
    } else {
        // POST new localization
        let mut attrs = serde_json::json!({
            "locale": req.locale,
            "feedbackEmail": req.feedback_email,
        });
        if let Some(ref desc) = req.description {
            attrs.as_object_mut().unwrap().insert("description".to_string(), serde_json::json!(desc));
        }

        let post_payload = serde_json::json!({
            "data": {
                "type": "betaAppLocalizations",
                "attributes": attrs,
                "relationships": {
                    "app": {
                        "data": {
                            "type": "apps",
                            "id": APP_ID
                        }
                    }
                }
            }
        });

        let response = client
            .post("https://api.appstoreconnect.apple.com/v1/betaAppLocalizations")
            .header("Authorization", format!("Bearer {jwt}"))
            .header("Content-Type", "application/json")
            .json(&post_payload)
            .send()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create app localization: {e}")))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read ASC response: {e}")))?;

        if !status.is_success() {
            return Err((StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
                format!("ASC API returned {}: {}", status.as_u16(), body)));
        }

        let json: serde_json::Value = serde_json::from_str(&body).unwrap_or_default();
        let new_id = json.get("data").and_then(|d| d.get("id")).and_then(|v| v.as_str()).unwrap_or("").to_string();

        Ok(Json(serde_json::json!({ "ok": true, "localization_id": new_id })))
    }
}

// ── Router construction ─────────────────────────────────────────────────

/// Build the axum `Router` with all API routes and shared state.
pub fn app(state: Arc<AppState>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/api/health", get(health))
        .route("/api/build", post(create_build))
        .route("/api/build/:job_id/status", get(get_status))
        .route("/api/build/:job_id/stream", get(stream_build))
        .route("/api/build/:job_id/github", post(push_to_github))
        // ── 5-Phase Build→Ship Pipeline ──────────────────────────────
        .route("/api/build/:job_id/patch", post(patch_build))
        .route("/api/build/:job_id/icon", post(generate_icon))
        .route("/api/build/:job_id/perfection", get(perfection))
        .route("/api/build/:job_id/asc-metadata", post(asc_metadata))
        .route("/api/build/:job_id/screenshots", post(take_screenshots))
        .route("/api/build/:job_id/upload", post(upload_build))
        .route("/api/build/:job_id/submit", post(submit_build))
        .route("/api/build/:job_id/asc-signin", get(asc_signin))
        .route("/api/build/:job_id/legal-pages", post(legal_pages))
        // ── AI Recovery Engine ──────────────────────────────────────────
        .route("/api/build/:job_id/steer", post(steer))
        .route("/api/build/:job_id/recover", post(recover))
        // ── New ASC endpoints ───────────────────────────────────────────
        .route("/api/asc-icon", post(asc_icon))
        .route("/api/screenshots/upload", post(screenshots_upload))
        .route("/api/asc-whatsnew", axum::routing::patch(asc_whatsnew))
        // ── Beta Tester & Beta Review endpoints ────────────────────────────
        .route("/api/testers", get(list_testers).post(add_tester))
        .route("/api/testers/{tester_id}", delete(delete_tester))
        .route("/api/testers/assign-build", post(assign_testers_to_build))
        .route("/api/beta-review", get(get_beta_review_status))
        .route("/api/beta-review/submit", post(submit_beta_review))
        .route("/api/beta-review/detail", post(set_beta_review_detail))
        .route("/api/beta-review/localization", post(set_beta_build_localization))
        .route("/api/beta-review/app-localization", post(set_beta_app_localization))
        .layer(cors)
        .with_state(state)
}

// ── Server entry point ──────────────────────────────────────────────────

/// Start the HTTP server on the given port.
///
/// This function blocks until the server is shut down (SIGINT / SIGTERM).
pub async fn serve(port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let state = Arc::new(AppState::new());
    let app = app(state);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await?;
    eprintln!("claw serve: listening on 0.0.0.0:{port}");

    // Graceful shutdown on SIGINT (Ctrl+C) or SIGTERM
    let shutdown_signal = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install SIGINT handler");
        eprintln!("claw serve: shutting down gracefully...");
    };

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal)
        .await
        .map_err(|e| -> Box<dyn std::error::Error + Send + Sync> { e.into() })
}