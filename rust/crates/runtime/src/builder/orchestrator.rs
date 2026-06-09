//! Build orchestrator – drives the full build pipeline.
//!
//! The orchestrator receives a [`BuildRequest`], plans the project, calls the AI,
//! writes files, compiles, and reports status through a tokio broadcast channel.

use crate::builder::github;
use crate::builder::project;
use crate::builder::prompts;
use crate::builder::{BuildEvent, BuildJob, BuildStatus};
use serde::Deserialize;
use std::path::PathBuf;
use tokio::sync::broadcast;

/// A single file produced by the AI, with its relative path and content.
#[derive(Debug, Clone, Deserialize)]
pub struct GeneratedFile {
    pub path: String,
    pub content: String,
}

/// Configuration for the AI call.
#[derive(Debug, Clone)]
pub struct AiConfig {
    /// `Anthropic` API key (from `ANTHROPIC_API_KEY` env var or [`BuildRequest`] override).
    pub api_key: String,
    /// Model to use (defaults to `claude-sonnet-4-20250514`).
    pub model: String,
}

/// Run the orchestrator pipeline for a single build job.
///
/// This performs the full pipeline:
/// 1. Scaffolding — create the on-disk project directory
/// 2. AI generation — call `Anthropic` API to generate Swift files
/// 3. Write generated files to disk
/// 4. Linting / compilation
/// 5. Optionally init git and push
/// 6. Open in Xcode
///
/// Status transitions are broadcast through the provided channel.
pub async fn run_build(
    job: &mut BuildJob,
    tx: &broadcast::Sender<BuildEvent>,
    ai_config: AiConfig,
) -> Result<PathBuf, String> {
    // Helper to transition status and broadcast.
    let set_status = |job: &mut BuildJob, status: BuildStatus| {
        job.status = status.clone();
        let _ = tx.send(BuildEvent::StageTransition { state: status });
    };

    // Helper to broadcast a log message.
    let log = |message: &str| {
        let _ = tx.send(BuildEvent::Log {
            message: message.to_string(),
        });
    };

    // ── Stage: Scaffolding ──────────────────────────────────────────────
    set_status(job, BuildStatus::Scaffolding);
    log("Creating project directory structure...");
    let project_path = project::scaffold_project(&job.request)?;
    job.project_path = project_path.to_string_lossy().to_string();
    log(&format!("Project scaffolded at {}", job.project_path));

    // ── Stage: Generating UI ────────────────────────────────────────────
    set_status(job, BuildStatus::GeneratingUI);
    log("Calling AI to generate Swift files...");
    let generated_files = match call_ai_for_files(&job.request, &ai_config).await {
        Ok(files) => files,
        Err(e) => {
            let error_msg = format!("AI generation failed: {e}");
            log(&error_msg);
            job.status = BuildStatus::Failed;
            job.error = Some(error_msg.clone());
            let _ = tx.send(BuildEvent::Failed {
                error: error_msg.clone(),
            });
            return Err(error_msg);
        }
    };
    log(&format!("AI generated {} file(s)", generated_files.len()));

    // ── Stage: Wiring Logic (write files to disk) ───────────────────────
    set_status(job, BuildStatus::WiringLogic);
    log("Writing generated files to disk...");
    for file in &generated_files {
        let file_path = project_path.join(&file.path);
        // Create parent directories if needed
        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create directory {}: {e}", file.path))?;
        }
        std::fs::write(&file_path, &file.content)
            .map_err(|e| format!("Failed to write file {}: {e}", file.path))?;
        log(&format!("Wrote {}", file.path));
    }

    // ── Stage: Linting ───────────────────────────────────────────────────
    set_status(job, BuildStatus::Linting);
    log("Running swift build to check compilation...");
    let build_result = run_swift_build(&project_path).await;
    match build_result {
        Ok(output) => {
            log(&format!("Build output:\n{output}"));
        }
        Err(e) => {
            log(&format!("Build reported issues (non-fatal): {e}"));
            // We don't fail here — the project may still be openable in Xcode
            // for the user to fix compilation errors.
        }
    }

    // ── Stage: Building IPA ──────────────────────────────────────────────
    set_status(job, BuildStatus::BuildingIPA);
    log("Attempting xcodebuild...");
    let xcodebuild_result = run_xcodebuild(&project_path).await;
    match xcodebuild_result {
        Ok(output) => {
            log(&format!("xcodebuild output:\n{output}"));
        }
        Err(e) => {
            log(&format!("xcodebuild not available or failed: {e}"));
            // Non-fatal: swift build output above is sufficient.
        }
    }

    // ── Git init ─────────────────────────────────────────────────────────
    let repo_name = github::repo_name_for(&job.request);
    if let Err(e) = github::init_and_push(&repo_name, &job.project_path) {
        log(&format!("Git init/push skipped or failed: {e}"));
    }

    // ── Open in Xcode ────────────────────────────────────────────────────
    log("Opening project in Xcode...");
    if let Err(e) = open_in_xcode(&job.project_path) {
        log(&format!("Could not open Xcode: {e}"));
    }

    // ── Complete ─────────────────────────────────────────────────────────
    set_status(job, BuildStatus::Completed);
    let _ = tx.send(BuildEvent::Completed {
        project_path: job.project_path.clone(),
    });
    log(&format!("Build complete! Project at {}", job.project_path));
    Ok(project_path)
}

/// Call the `Anthropic` Messages API to generate Swift files.
///
/// Sends the system + user prompt and parses the response as a JSON array
/// of `{path, content}` objects. Strips markdown code fences if present.
async fn call_ai_for_files(
    request: &crate::builder::BuildRequest,
    ai_config: &AiConfig,
) -> Result<Vec<GeneratedFile>, String> {
    let system_prompt = prompts::system_prompt_for_build();
    let user_prompt = prompts::user_prompt_for_build(request);

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300)) // 5 min timeout for AI calls
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {e}"))?;

    let model = ai_config.model.clone();

    let body = serde_json::json!({
        "model": model,
        "max_tokens": 8192,
        "system": system_prompt,
        "messages": [
            {
                "role": "user",
                "content": user_prompt
            }
        ]
    });

    let response = client
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", &ai_config.api_key)
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("HTTP request to Anthropic API failed: {e}"))?;

    if !response.status().is_success() {
        let status = response.status();
        let body_text = response.text().await.unwrap_or_default();
        return Err(format!("Anthropic API returned {status}: {body_text}"));
    }

    let response_json: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Anthropic API response: {e}"))?;

    // Extract the text content from the response
    let content_blocks = response_json
        .get("content")
        .and_then(|c| c.as_array())
        .ok_or_else(|| "Anthropic API response missing 'content' array".to_string())?;

    let mut full_text = String::new();
    for block in content_blocks {
        if block.get("type").and_then(|t| t.as_str()) == Some("text") {
            if let Some(text) = block.get("text").and_then(|t| t.as_str()) {
                full_text.push_str(text);
            }
        }
    }

    // Strip markdown code fences if present
    let json_text = strip_markdown_fences(&full_text);

    // Parse as JSON array of GeneratedFile
    let files: Vec<GeneratedFile> = serde_json::from_str(&json_text).map_err(|e| {
        format!(
            "Failed to parse AI response as JSON array of files: {e}\n\nRaw text:\n{full_text}"
        )
    })?;

    Ok(files)
}

/// Strip markdown code fences (```json ... ```) from AI response text.
///
/// If the text starts with ``` and ends with ```, strip those fences and
/// return the inner content. Otherwise return as-is.
fn strip_markdown_fences(text: &str) -> String {
    let trimmed = text.trim();

    // Try to detect and strip ```json ... ``` blocks
    if trimmed.starts_with("```") {
        // Use strip_prefix instead of manual slicing
        let after_first_fence = trimmed.strip_prefix("```").unwrap_or(trimmed);
        let lang_end = match after_first_fence.find('\n') {
            Some(i) => i + 1,
            None => return text.to_string(),
        };
        // Find the closing ```
        let closing = trimmed.rfind("```");
        if let Some(closing_pos) = closing {
            if closing_pos > lang_end {
                return trimmed[lang_end..closing_pos].trim().to_string();
            }
        }
    }

    // If the text itself is valid JSON, return it
    if trimmed.starts_with('[') {
        return trimmed.to_string();
    }

    // Try harder: look for the first `[` and last `]`
    if let Some(start) = trimmed.find('[') {
        if let Some(end) = trimmed.rfind(']') {
            if end > start {
                return trimmed[start..=end].to_string();
            }
        }
    }

    text.to_string()
}

/// Run `swift build` in the project directory.
async fn run_swift_build(project_path: &PathBuf) -> Result<String, String> {
    let output = tokio::process::Command::new("swift")
        .arg("build")
        .arg("--package-path")
        .arg(project_path)
        .output()
        .await
        .map_err(|e| format!("Failed to run swift build: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    if output.status.success() {
        Ok(format!("{stdout}\n{stderr}"))
    } else {
        Err(format!(
            "swift build exited with {}:\n{stdout}\n{stderr}",
            output.status.code().unwrap_or(-1)
        ))
    }
}

/// Run `xcodebuild` in the project directory (best-effort).
async fn run_xcodebuild(project_path: &PathBuf) -> Result<String, String> {
    // Try to build using the Package.swift — xcodebuild can handle SPM projects
    let output = tokio::process::Command::new("xcodebuild")
        .arg("build")
        .arg("-scheme")
        .arg("Placeholder") // Will likely fail, but we try
        .arg("-project")
        .arg(project_path)
        .output()
        .await
        .map_err(|e| format!("xcodebuild not available: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    if output.status.success() {
        Ok(format!("{stdout}\n{stderr}"))
    } else {
        Err(format!(
            "xcodebuild exited with {}:\n{stdout}\n{stderr}",
            output.status.code().unwrap_or(-1)
        ))
    }
}

/// Open the project in Xcode.
fn open_in_xcode(project_path: &str) -> Result<(), String> {
    std::process::Command::new("open")
        .arg("-a")
        .arg("Xcode")
        .arg(project_path)
        .spawn()
        .map_err(|e| format!("Failed to open Xcode: {e}"))?;
    Ok(())
}

/// Resolve the AI config from the [`BuildRequest`] and environment.
pub fn resolve_ai_config(request: &crate::builder::BuildRequest) -> Result<AiConfig, String> {
    let api_key = request
        .api_key
        .clone()
        .or_else(|| std::env::var("ANTHROPIC_API_KEY").ok())
        .ok_or_else(|| {
            "No API key provided. Set ANTHROPIC_API_KEY or pass api_key in the request.".to_string()
        })?;

    let model = request
        .model
        .clone()
        .unwrap_or_else(|| "claude-sonnet-4-20250514".to_string());

    Ok(AiConfig { api_key, model })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strip_markdown_fences_json_block() {
        let input = "```json\n[{\"path\": \"foo.swift\", \"content\": \"bar\"}]\n```";
        let result = strip_markdown_fences(input);
        assert!(result.starts_with('['));
        assert!(result.ends_with(']'));
    }

    #[test]
    fn test_strip_markdown_fences_plain_json() {
        let input = r#"[{"path": "foo.swift", "content": "bar"}]"#;
        let result = strip_markdown_fences(input);
        assert_eq!(result, input);
    }

    #[test]
    fn test_strip_markdown_fences_with_surrounding_text() {
        let input = "Here are the files:\n[{\"path\": \"foo.swift\", \"content\": \"bar\"}]\nHope that helps!";
        let result = strip_markdown_fences(input);
        assert!(result.starts_with('['));
        assert!(result.ends_with(']'));
    }
}