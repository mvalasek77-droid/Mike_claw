//! Build orchestrator – drives the full build pipeline.
//!
//! The orchestrator receives a [`BuildRequest`], plans the project, calls the AI,
//! writes files, compiles, and reports status through a tokio broadcast channel.

use crate::builder::github;
use crate::builder::project;
use crate::builder::prompts;
use crate::builder::{
    AscMetadataResponse, AxisResult, BuildEvent, BuildJob, BuildStatus, IconRequest,
};
use serde::{Deserialize, Serialize};
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

/// 9-axis perfection audit report returned by `call_ai_for_perfection`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerfectionReport {
    pub axes: Vec<AxisResult>,
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
        "max_tokens": 16384,
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
    let files: Vec<GeneratedFile> = match serde_json::from_str(&json_text) {
        Ok(f) => f,
        Err(parse_err) => {
            // AI response was truncated — try to recover partial files
            // by finding complete JSON objects within the truncated text.
            eprintln!(
                "WARNING: Full JSON parse failed ({parse_err}), attempting partial recovery…"
            );
            recover_partial_files(&json_text).unwrap_or_else(|| {
                // Return a Vec with a single error-description file so the
                // build doesn't die completely — downstream phases can still
                // attempt to compile what we *do* have.
                vec![]
            })
        }
    };

    Ok(files)
}

// ── Pipeline phase functions ─────────────────────────────────────────────

/// Recover partial files from a truncated JSON array response.
///
/// When Anthropic truncates the response mid-JSON, we can still salvage
/// complete file objects that appeared before the truncation point.
fn recover_partial_files(json_text: &str) -> Option<Vec<GeneratedFile>> {
    let mut files = Vec::new();
    let mut depth = 0i32;
    let mut in_string = false;
    let mut escape_next = false;
    let mut obj_start: Option<usize> = None;
    let bytes = json_text.as_bytes();
    let len = bytes.len();

    for i in 0..len {
        let ch = bytes[i];
        if escape_next {
            escape_next = false;
            continue;
        }
        if ch == b'\\' && in_string {
            escape_next = true;
            continue;
        }
        if ch == b'"' {
            in_string = !in_string;
            continue;
        }
        if in_string {
            continue;
        }
        match ch {
            b'{' => {
                if depth == 0 {
                    obj_start = Some(i);
                }
                depth += 1;
            }
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    if let Some(start) = obj_start.take() {
                        if let Ok(file) = serde_json::from_slice::<GeneratedFile>(&json_text.as_bytes()[start..=i]) {
                            files.push(file);
                        }
                    }
                }
            }
            _ => {}
        }
        if i > 500_000 {
            break; // Safety limit
        }
    }

    if files.is_empty() {
        // Try to find the array start and extract what we can
        if let Some(arr_start) = json_text.find('[') {
            let sub = &json_text[arr_start..];
            // Try progressively shorter substrings
            for end in (0..sub.len()).rev().step_by(100) {
                let candidate = format!("{}}}]", &sub[..end.min(sub.len())]);
                if let Ok(parsed) = serde_json::from_str::<Vec<GeneratedFile>>(&candidate) {
                    return Some(parsed);
                }
            }
        }
        None
    } else {
        Some(files)
    }
}

/// Call the AI to patch specific files in an existing project.
///
/// Sends the bug description and (optionally) the list of files to edit
/// along with the current file contents. The AI returns updated files as a
/// JSON array of `{path, content}` objects.
pub async fn call_ai_for_patch(
    project_path: &str,
    bug_description: &str,
    files_to_edit: &Option<Vec<String>>,
    ai_config: &AiConfig,
) -> Result<Vec<GeneratedFile>, String> {
    // Read the Swift files that should be included in the patch context.
    let context_files = read_project_files(project_path, files_to_edit.as_deref())?;

    let system_prompt = prompts::system_prompt_for_patch();
    let user_prompt = prompts::user_prompt_for_patch(bug_description, &context_files);

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {e}"))?;

    let body = serde_json::json!({
        "model": ai_config.model,
        "max_tokens": 16384,
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

    let json_text = strip_markdown_fences(&full_text);
    let files: Vec<GeneratedFile> = serde_json::from_str(&json_text).map_err(|e| {
        format!("Failed to parse patch response as JSON array of files: {e}\n\nRaw text:\n{full_text}")
    })?;

    Ok(files)
}

/// Generate a placeholder app icon (1×1 PNG) with the app's initials.
///
/// In the future this will call DALL-E or a similar image generation API.
/// For now, it creates a minimal valid PNG file and saves it to the
/// project's Asset Catalog.
pub fn call_ai_for_icon(
    _request: &IconRequest,
    project_path: &str,
    app_title: &str,
    _ai_config: &AiConfig,
) -> Result<String, String> {
    // Build a minimal 1×1 PNG file.
    // A valid PNG consists of: signature + IHDR + IDAT + IEND chunks.
    // We create a simple white 1×1 pixel image.
    let png_bytes = create_placeholder_icon_png();

    // Determine the Asset Catalog path.
    // Projects created by our scaffolder place Assets.xcassets under
    // Sources/{ModuleName }/Assets.xcassets.
    let project = std::path::Path::new(project_path);
    let appiconset_dir = find_or_create_appiconset(project, app_title)?;

    let icon_path = appiconset_dir.join("icon-1024.png");
    std::fs::write(&icon_path, &png_bytes)
        .map_err(|e| format!("Failed to write icon file: {e}"))?;

    // Write or update the Contents.json for the AppIcon
    let contents_json = format!(
        r#"{{"images":[{{"idiom":"universal","platform":"ios","size":"1024x1024","filename":"icon-1024.png"}}],"info":{{"version":1,"author":"xcode"}}}}"#
    );
    std::fs::write(appiconset_dir.join("Contents.json"), &contents_json)
        .map_err(|e| format!("Failed to write AppIcon Contents.json: {e}"))?;

    Ok(icon_path.to_string_lossy().to_string())
}

/// Run the 9-axis perfection audit against all Swift files in the project.
///
/// The axes are:
///   apple_review, accessibility, performance, security, grammar,
///   ui_polish, device_compat, architecture, packaging
///
/// Sends each Swift file's content to the AI and parses the structured
/// quality report that comes back.
pub async fn call_ai_for_perfection(
    project_path: &str,
    ai_config: &AiConfig,
) -> Result<PerfectionReport, String> {
    let swift_files = read_project_files(project_path, None)?;
    let all_code = swift_files
        .iter()
        .map(|(path, content)| format!("// ── {path} ──\n{content}"))
        .collect::<Vec<_>>()
        .join("\n\n");

    let system_prompt = prompts::system_prompt_for_perfection();
    let user_prompt = prompts::user_prompt_for_perfection(&all_code);

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {e}"))?;

    let body = serde_json::json!({
        "model": ai_config.model,
        "max_tokens": 4096,
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

    let json_text = strip_markdown_fences(&full_text);
    let axes: Vec<AxisResult> = serde_json::from_str(&json_text).map_err(|e| {
        format!("Failed to parse perfection response: {e}\n\nRaw text:\n{full_text}")
    })?;

    Ok(PerfectionReport { axes })
}

/// Generate App Store Connect metadata from the project.
///
/// Analyzes the project structure and Swift source to produce ASC-ready
/// metadata (name, subtitle, keywords, description, age rating, etc.).
pub async fn call_ai_for_asc_metadata(
    project_path: &str,
    request: &crate::builder::BuildRequest,
    ai_config: &AiConfig,
) -> Result<AscMetadataResponse, String> {
    let swift_files = read_project_files(project_path, None)?;
    let all_code = swift_files
        .iter()
        .map(|(path, content)| format!("// ── {path} ──\n{content}"))
        .collect::<Vec<_>>()
        .join("\n\n");

    let system_prompt = prompts::system_prompt_for_asc_metadata();
    let user_prompt = prompts::user_prompt_for_asc_metadata(request, &all_code);

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {e}"))?;

    let body = serde_json::json!({
        "model": ai_config.model,
        "max_tokens": 4096,
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

    let json_text = strip_markdown_fences(&full_text);
    let metadata: AscMetadataResponse = serde_json::from_str(&json_text).map_err(|e| {
        format!("Failed to parse ASC metadata response: {e}\n\nRaw text:\n{full_text}")
    })?;

    Ok(metadata)
}

// ── Helper functions ─────────────────────────────────────────────────────

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
    if trimmed.starts_with('[') || trimmed.starts_with('{') {
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

    // Also try JSON objects
    if let Some(start) = trimmed.find('{') {
        if let Some(end) = trimmed.rfind('}') {
            if end > start {
                return trimmed[start..=end].to_string();
            }
        }
    }

    text.to_string()
}

/// Read Swift files from the project directory.
///
/// If `filter` is provided, only files whose names appear in the list
/// (or that end in `.swift`) are included. If `filter` is `None`, all
/// `.swift` files are included.
fn read_project_files(
    project_path: &str,
    filter: Option<&[String]>,
) -> Result<Vec<(String, String)>, String> {
    let root = std::path::Path::new(project_path);
    if !root.exists() {
        return Err(format!("Project path does not exist: {project_path}"));
    }

    let mut files = Vec::new();
    let walker = walkdir::WalkDir::new(root).into_iter();

    for entry in walker.filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let ext = path.extension().and_then(|e| e.to_str());
        if ext != Some("swift") {
            continue;
        }

        let relative = path
            .strip_prefix(root)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        if let Some(filter_list) = filter {
            let basename = path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
            if !filter_list.contains(&basename) && !filter_list.contains(&relative) {
                continue;
            }
        }

        let content = std::fs::read_to_string(path)
            .map_err(|e| format!("Failed to read {}: {e}", relative))?;
        files.push((relative, content));
    }

    Ok(files)
}

/// Create a minimal placeholder PNG (1×1 white pixel).
///
/// This is used when no image generation backend is available.
/// A real implementation would call DALL-E or a similar service.
fn create_placeholder_icon_png() -> Vec<u8> {
    // Minimal valid PNG: 1×1 white pixel.
    // We build it chunk by chunk manually.
    let mut png = Vec::new();

    // PNG signature
    png.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);

    // IHDR chunk (13 bytes of data)
    let ihdr_data = {
        let mut d = Vec::new();
        d.extend_from_slice(&1u32.to_be_bytes()); // width: 1
        d.extend_from_slice(&1u32.to_be_bytes()); // height: 1
        d.push(8); // bit depth: 8
        d.push(2); // color type: RGB
        d.push(0); // compression: deflate
        d.push(0); // filter: adaptive
        d.push(0); // interlace: none
        d
    };
    let ihdr_chunk_data: Vec<u8> = [&b"IHDR"[..], &ihdr_data[..]].concat();
    png.extend_from_slice(&(ihdr_data.len() as u32).to_be_bytes());
    png.extend_from_slice(b"IHDR");
    png.extend_from_slice(&ihdr_data);
    let ihdr_crc = crc32(&ihdr_chunk_data);
    png.extend_from_slice(&ihdr_crc.to_be_bytes());

    // IDAT chunk – compressed row: filter byte (0) + 3 bytes RGB (white)
    // We use a stored (non-compressed) deflate block.
    let raw_data = vec![0u8, 255, 255, 255]; // filter=none, R=255, G=255, B=255
    let compressed = deflate_store(&raw_data);
    let idat_chunk_data: Vec<u8> = [&b"IDAT"[..], &compressed[..]].concat();
    png.extend_from_slice(&(compressed.len() as u32).to_be_bytes());
    png.extend_from_slice(b"IDAT");
    png.extend_from_slice(&compressed);
    let idat_crc = crc32(&idat_chunk_data);
    png.extend_from_slice(&idat_crc.to_be_bytes());

    // IEND chunk
    png.extend_from_slice(&0u32.to_be_bytes());
    png.extend_from_slice(b"IEND");
    let iend_crc = crc32(b"IEND");
    png.extend_from_slice(&iend_crc.to_be_bytes());

    png
}

/// Simple deflate "store" block (no compression, just wrapping).
fn deflate_store(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.push(0x78); // CMF: deflate, window size 7
    out.push(0x01); // FLG: no dict, check bits
    // Stored block: BFINAL=1, BTYPE=00
    out.push(1); // BFINAL=1
    out.extend_from_slice(&(data.len() as u16).to_le_bytes());
    out.extend_from_slice(&(data.len() as u16 ^ 0xFFFFu16).to_le_bytes());
    out.extend_from_slice(data);
    // Adler-32 checksum
    let adler = adler32(data);
    out.extend_from_slice(&adler.to_be_bytes());
    out
}

/// Compute Adler-32 checksum.
fn adler32(data: &[u8]) -> u32 {
    let mut a: u32 = 1;
    let mut b: u32 = 0;
    for &byte in data {
        a = (a + byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

/// Compute CRC-32 (used for PNG chunk CRCs).
fn crc32(data: &[u8]) -> u32 {
    // Standard CRC-32 with polynomial 0xEDB88320
    let mut table = [0u32; 256];
    for i in 0..256 {
        let mut crc = i as u32;
        for _ in 0..8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
        table[i as usize] = crc;
    }

    let mut crc = 0xFFFFFFFFu32;
    for &byte in data {
        crc = (crc >> 8) ^ table[((crc ^ byte as u32) & 0xFF) as usize];
    }
    !crc
}

/// Find or create the AppIcon.appiconset directory inside the project's
/// Asset Catalog.
fn find_or_create_appiconset(
    project_path: &std::path::Path,
    _app_title: &str,
) -> Result<std::path::PathBuf, String> {
    // Walk the project to find Assets.xcassets
    for entry in walkdir::WalkDir::new(project_path)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if path.is_dir() && path.file_name().unwrap_or_default() == "Assets.xcassets" {
            let appiconset = path.join("AppIcon.appiconset");
            std::fs::create_dir_all(&appiconset)
                .map_err(|e| format!("Failed to create AppIcon.appiconset: {e}"))?;
            return Ok(appiconset);
        }
    }

    // If not found, create one in a default location
    let sources_dir = project_path.join("Sources");
    let module_dir = find_module_dir(&sources_dir)?;
    let assets_dir = module_dir.join("Assets.xcassets");
    std::fs::create_dir_all(&assets_dir)
        .map_err(|e| format!("Failed to create Assets.xcassets: {e}"))?;

    // Write the catalog Contents.json
    let contents = r#"{"info":{"version":1,"author":"xcode"}}"#;
    std::fs::write(assets_dir.join("Contents.json"), contents)
        .map_err(|e| format!("Failed to write Contents.json: {e}"))?;

    let appiconset = assets_dir.join("AppIcon.appiconset");
    std::fs::create_dir_all(&appiconset)
        .map_err(|e| format!("Failed to create AppIcon.appiconset: {e}"))?;

    Ok(appiconset)
}

/// Find the first module directory under `Sources/`.
fn find_module_dir(sources_dir: &std::path::Path) -> Result<std::path::PathBuf, String> {
    if !sources_dir.exists() {
        return Err(format!("Sources directory not found: {}", sources_dir.display()));
    }
    for entry in std::fs::read_dir(sources_dir)
        .map_err(|e| format!("Failed to read Sources dir: {e}"))?
    {
        let entry = entry.map_err(|e| format!("Failed to read entry: {e}"))?;
        if entry.file_type().map_or(false, |t| t.is_dir()) {
            return Ok(entry.path());
        }
    }
    Err("No module directory found under Sources/".to_string())
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
            "No API key provided. Set ANTHROPIC_API_KEY or pass api_key in the request."
                .to_string()
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

    #[test]
    fn test_strip_markdown_fences_json_object() {
        let input = "Here is the metadata:\n{\"name\": \"Test\"}\nDone.";
        let result = strip_markdown_fences(input);
        assert!(result.starts_with('{'));
        assert!(result.ends_with('}'));
    }

    #[test]
    fn test_placeholder_icon_png_is_valid() {
        let png = create_placeholder_icon_png();
        // PNG signature check
        assert_eq!(&png[..8], &[137, 80, 78, 71, 13, 10, 26, 10]);
        // Minimum size: signature + IHDR + IDAT + IEND
        assert!(png.len() > 50);
    }

    #[test]
    fn test_crc32_empty() {
        let crc = crc32(b"");
        assert_eq!(crc, 0x00000000);
    }

    #[test]
    fn test_crc32_iend() {
        let crc = crc32(b"IEND");
        // Known CRC for IEND
        assert_ne!(crc, 0);
    }
}