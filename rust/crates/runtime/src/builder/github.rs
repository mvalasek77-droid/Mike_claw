//! GitHub operations for the builder.
//!
//! Initializes a git repository and pushes it to a remote. Uses synchronous
//! `std::process::Command` for the non-async path and `tokio::process::Command`
//! for the async path.

use crate::builder::BuildRequest;
use std::process::Command;

/// Compute the target repo name for a build request.
///
/// Slug-ifies the title: lowercase, spaces → hyphens, strip non-alphanumeric.
#[must_use]
pub fn repo_name_for(request: &BuildRequest) -> String {
    request
        .title
        .to_lowercase()
        .replace(' ', "-")
        .replace(|c: char| !c.is_alphanumeric() && c != '-', "")
}

/// Initialize a git repository and push to the origin remote.
///
/// This is a best-effort operation — if git is unavailable or the remote
/// push fails, the build still completes (the project exists on disk).
/// Uses synchronous `std::process::Command` since this is called from
/// the orchestrator's post-build phase.
pub fn init_and_push(repo_name: &str, project_path: &str) -> Result<(), String> {
    // git init
    let init_output = Command::new("git")
        .arg("init")
        .arg(project_path)
        .output()
        .map_err(|e| format!("Failed to run git init: {e}"))?;

    if !init_output.status.success() {
        let stderr = String::from_utf8_lossy(&init_output.stderr);
        return Err(format!("git init failed: {stderr}"));
    }

    // git add -A
    let add_output = Command::new("git")
        .current_dir(project_path)
        .args(["add", "-A"])
        .output()
        .map_err(|e| format!("Failed to run git add: {e}"))?;

    if !add_output.status.success() {
        let stderr = String::from_utf8_lossy(&add_output.stderr);
        return Err(format!("git add failed: {stderr}"));
    }

    // git commit
    let commit_output = Command::new("git")
        .current_dir(project_path)
        .args([
            "commit",
            "-m",
            &format!("Initial commit for {repo_name}"),
            "--allow-empty",
        ])
        .env("GIT_AUTHOR_NAME", "CodeGenie")
        .env("GIT_AUTHOR_EMAIL", "codegenie@clawcode.dev")
        .env("GIT_COMMITTER_NAME", "CodeGenie")
        .env("GIT_COMMITTER_EMAIL", "codegenie@clawcode.dev")
        .output()
        .map_err(|e| format!("Failed to run git commit: {e}"))?;

    if !commit_output.status.success() {
        let stderr = String::from_utf8_lossy(&commit_output.stderr);
        return Err(format!("git commit failed: {stderr}"));
    }

    // Note: We don't push by default — the user needs to configure a remote
    // and authentication. This is intentional for security.
    // If a remote is configured, push it.
    let remote_check = Command::new("git")
        .current_dir(project_path)
        .args(["remote", "get-url", "origin"])
        .output();

    if let Ok(output) = remote_check {
        if output.status.success() {
            let _push_output = Command::new("git")
                .current_dir(project_path)
                .args(["push", "-u", "origin", "HEAD"])
                .output();
            // Best-effort push — ignore errors
        }
    }

    Ok(())
}

/// Async version of git init + push for use in async contexts.
pub async fn init_and_push_async(repo_name: &str, project_path: &str) -> Result<(), String> {
    // git init
    let init_output = tokio::process::Command::new("git")
        .arg("init")
        .arg(project_path)
        .output()
        .await
        .map_err(|e| format!("Failed to run git init: {e}"))?;

    if !init_output.status.success() {
        let stderr = String::from_utf8_lossy(&init_output.stderr);
        return Err(format!("git init failed: {stderr}"));
    }

    // git add -A
    let add_output = tokio::process::Command::new("git")
        .current_dir(project_path)
        .args(["add", "-A"])
        .output()
        .await
        .map_err(|e| format!("Failed to run git add: {e}"))?;

    if !add_output.status.success() {
        let stderr = String::from_utf8_lossy(&add_output.stderr);
        return Err(format!("git add failed: {stderr}"));
    }

    // git commit
    let commit_output = tokio::process::Command::new("git")
        .current_dir(project_path)
        .args([
            "commit",
            "-m",
            &format!("Initial commit for {repo_name}"),
            "--allow-empty",
        ])
        .env("GIT_AUTHOR_NAME", "CodeGenie")
        .env("GIT_AUTHOR_EMAIL", "codegenie@clawcode.dev")
        .env("GIT_COMMITTER_NAME", "CodeGenie")
        .env("GIT_COMMITTER_EMAIL", "codegenie@clawcode.dev")
        .output()
        .await
        .map_err(|e| format!("Failed to run git commit: {e}"))?;

    if !commit_output.status.success() {
        let stderr = String::from_utf8_lossy(&commit_output.stderr);
        return Err(format!("git commit failed: {stderr}"));
    }

    // Try to push if a remote is configured
    let remote_check = tokio::process::Command::new("git")
        .current_dir(project_path)
        .args(["remote", "get-url", "origin"])
        .output()
        .await;

    if let Ok(output) = remote_check {
        if output.status.success() {
            let _push_output = tokio::process::Command::new("git")
                .current_dir(project_path)
                .args(["push", "-u", "origin", "HEAD"])
                .output()
                .await;
            // Best-effort — ignore push errors
        }
    }

    Ok(())
}