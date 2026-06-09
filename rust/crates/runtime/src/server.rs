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

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::sse::{Event, KeepAlive, Sse},
    routing::{get, post},
    Json, Router,
};
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
    resolve_ai_config,
};
use crate::builder::project;
use crate::builder::{
    AscMetadataResponse, BuildEvent, BuildJob, BuildRequest, BuildStatus, IconRequest, PatchRequest,
    PerfectionResponse, ScreenshotsResponse, SubmitResponse, UploadResponse,
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
/// This is a placeholder that records the intent to take screenshots. A real
/// implementation would drive XCUITest or a simulator to capture screenshots.
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

    let project_path = {
        let job = job_arc.lock().await;
        job.project_path.clone()
    };

    // Transition to TakingScreenshots
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::TakingScreenshots;
    }

    // Placeholder: create a screenshots directory and indicate where
    // screenshots would be saved. A real implementation would run
    // `xcrun simctl io` or `xcodebuild test` with a screenshot plan.
    let screenshots_dir = std::path::Path::new(&project_path).join("Screenshots");
    std::fs::create_dir_all(&screenshots_dir)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create Screenshots dir: {e}")))?;

    // Placeholder screenshot paths — the real automation would populate these.
    let screenshot_paths = vec![
        "Screenshots/iphone_6.7_01.png".to_string(),
        "Screenshots/iphone_6.7_02.png".to_string(),
        "Screenshots/iphone_6.7_03.png".to_string(),
        "Screenshots/ipad_12.9_01.png".to_string(),
        "Screenshots/ipad_12.9_02.png".to_string(),
    ];

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    Ok(Json(ScreenshotsResponse {
        job_id,
        status: "taking_screenshots".to_string(),
        screenshot_paths,
    }))
}

/// `POST /api/build/:job_id/upload` — Archive and upload the build to ASC.
///
/// This is a placeholder. A real implementation would run `xcodebuild archive`
/// and `xcrun altool --upload-app` or use the newer `xcrun notarytool`.
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

    let project_path = {
        let job = job_arc.lock().await;
        job.project_path.clone()
    };

    // Transition to UploadingASC
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::UploadingASC;
    }

    // Placeholder: construct an archive path.
    // A real implementation would run:
    //   xcodebuild archive -project ... -scheme ... -archivePath ...
    //   xcodebuild -exportArchive -exportOptionsPlist ... ...
    //   xcrun altool --upload-app ...
    let archive_path = std::path::Path::new(&project_path)
        .join("build")
        .join("Archive.xcarchive")
        .to_string_lossy()
        .to_string();

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    Ok(Json(UploadResponse {
        job_id,
        status: "uploading".to_string(),
        archive_path,
    }))
}

/// `POST /api/build/:job_id/submit` — Submit for App Store review.
///
/// This is a placeholder. A real implementation would call the App Store
/// Connect API to submit the app for review.
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

    // Transition to Submitting
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Submitting;
    }

    // Placeholder: a real implementation would call the App Store Connect API
    // via the `altool`/`notarytool` CLI or direct HTTP API calls.

    // Transition back to Completed
    {
        let mut job = job_arc.lock().await;
        job.status = BuildStatus::Completed;
    }

    Ok(Json(SubmitResponse {
        job_id,
        status: "submitted".to_string(),
    }))
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