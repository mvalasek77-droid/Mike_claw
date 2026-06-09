//! HTTP server for the `CodeGenie` iPhone app.
//!
//! This module exposes an axum-based HTTP server that the `CodeGenie` iPhone
//! client can POST build requests to. Endpoints:
//!
//! - `GET  /api/health`                    – health / version check
//! - `POST /api/build`                     – submit a new build job
//! - `GET  /api/build/{job_id}/status`     – poll job status
//! - `GET  /api/build/{job_id}/stream`     – SSE stream of build events
//! - `POST /api/build/{job_id}/github`     – push to GitHub

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

use crate::builder::orchestrator::resolve_ai_config;
use crate::builder::project;
use crate::builder::{BuildEvent, BuildJob, BuildRequest, BuildStatus};

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