//! Prompt templates used by the builder orchestrator.
//!
//! These prompts instruct the AI to generate Swift files for an iOS app,
//! patch bugs, audit quality, generate metadata, etc.

use crate::builder::BuildRequest;

/// Build the system prompt that instructs the AI to generate an iOS project.
///
/// The AI is told to output a JSON array of file objects. Each object has
/// `path` (relative to the project root) and `content` (the file contents).
#[must_use]
pub fn system_prompt_for_build() -> String {
    "You are an expert iOS developer specializing in SwiftUI. Your task is to generate a complete, buildable iOS app project based on the user's description.\n\n\
     RULES:\n\
     1. Output ONLY a JSON array of file objects. No prose, no explanations, no markdown.\n\
     2. Each file object has two keys: \"path\" (relative path from the project root) and \"content\" (the complete file contents as a string).\n\
     3. The project uses SwiftUI and targets the iOS version specified in the user prompt.\n\
     4. Do NOT include Package.swift — the project scaffold is already created. Your files go into the Sources/ directory.\n\
     5. Provide at minimum:\n\
        - A ContentView.swift with the main UI\n\
        - Any additional Swift files for models, views, or services the app needs\n\
     6. All files must compile together as a cohesive SwiftUI application.\n\
     7. Use modern Swift concurrency (@MainActor, async/await) where appropriate.\n\
     8. Follow Apple's Human Interface Guidelines for the specified visual style.\n\
     9. Ensure all navigation uses NavigationStack (iOS 16+) or NavigationView.\n\
     10. Use @State, @StateObject, @ObservedObject, @EnvironmentObject as appropriate.\n\n\
     OUTPUT FORMAT (strictly):\n\
     ```json\n\
     [\n\
       {\"path\": \"Sources/ModuleName/ContentView.swift\", \"content\": \"import SwiftUI\\n\\nstruct ContentView: View {\\n    var body: some View {\\n        Text(\\\"Hello\\\")\\n    }\\n}\"},\n\
       {\"path\": \"Sources/ModuleName/SomeModel.swift\", \"content\": \"import Foundation\\n// model code\"}\n\
     ]\n\
     ```\n\n\
     Remember: ONLY output the JSON array. No other text.".to_string()
}

/// Build the user-facing prompt from a [`BuildRequest`].
///
/// Incorporates the app spec: title, prompt, category, style, features, and
/// target iOS version.
#[must_use]
pub fn user_prompt_for_build(request: &BuildRequest) -> String {
    let features_str = if request.features.is_empty() {
        "None specified".to_string()
    } else {
        request.features.join(", ")
    };

    let module_name = sanitize_module_name(&request.title);

    format!(
        "Generate a complete SwiftUI iOS app with the following specification:\n\n\
         **App Title:** {title}\n\
         **Description:** {prompt}\n\
         **Category:** {category}\n\
         **Visual Style:** {style}\n\
         **Target iOS Version:** {target_ios}\n\
         **Features:** {features}\n\n\
         **Module Name:** {module_name}\n\n\
         Create all the Swift source files needed for this app. The module name is \"{module_name}\" — use this throughout the code for the SwiftUI App struct and any namespaced types. Place files under `Sources/{module_name}/`.\n\n\
         The app should be fully functional, visually polished, and match the described style. Include all necessary models, views, and any data services. Use SwiftUI best practices and modern APIs available in iOS {target_ios}+.",
        title = request.title,
        prompt = request.prompt,
        category = request.category,
        style = request.style,
        target_ios = request.target_ios,
        features = features_str,
        module_name = module_name,
    )
}

/// System prompt for the patch (bug-fix) phase.
///
/// Instructs the AI to fix a described bug by returning updated files.
#[must_use]
pub fn system_prompt_for_patch() -> String {
    "You are patching an iOS app. Fix the described bug by editing only the necessary files. \
     Output a JSON array of {\"path\", \"content\"} objects with the FULL updated file content. \
     Do NOT truncate — return the complete file contents for each file you modify. \
     Output ONLY the JSON array, no markdown, no prose.".to_string()
}

/// User prompt for the patch phase, including current file contents and bug description.
#[must_use]
pub fn user_prompt_for_patch(bug_description: &str, context_files: &[(String, String)]) -> String {
    let files_section = context_files
        .iter()
        .map(|(path, content)| format!("--- {path} ---\n{content}"))
        .collect::<Vec<_>>()
        .join("\n\n");

    format!(
        "The following bug needs to be fixed:\n\n\
         **Bug Description:** {bug_description}\n\n\
         Here are the current source files:\n\n\
         {files_section}\n\n\
         Return a JSON array of all files that need to change, with their complete updated content. \
         Only include files you actually modified. Use the same relative paths as above.",
        bug_description = bug_description,
        files_section = files_section,
    )
}

/// System prompt for the 9-axis perfection audit.
///
/// The AI must return a JSON array of axis results.
#[must_use]
pub fn system_prompt_for_perfection() -> String {
    "You are an expert iOS code auditor. Analyze the provided Swift source code against these 9 quality axes:\n\n\
     1. apple_review — Will the app pass App Store review guidelines?\n\
     2. accessibility — VoiceOver, Dynamic Type, contrast ratios, labels\n\
     3. performance — Main-thread safety, lazy loading, memory usage\n\
     4. security — Data protection, secure storage, input validation\n\
     5. grammar — Spelling, punctuation, wording in all user-facing strings\n\
     6. ui_polish — Consistent spacing, alignment, animations, edge cases\n\
     7. device_compat — iPhone/iPad/Mac, orientations, safe areas\n\
     8. architecture — SOLID principles, separation of concerns, testability\n\
     9. packaging — Bundle configuration, privacy manifest, entitlements\n\n\
     Output ONLY a JSON array with exactly 9 objects, one per axis:\n\
     ```json\n\
     [\n\
       {\"name\": \"apple_review\", \"passed\": 5, \"failed\": 0, \"confidence\": 0.9, \"recommendations\": [\"...\"]},\n\
       ...\n\
     ]\n\
     ```\n\
     No prose, no markdown — just the JSON array.".to_string()
}

/// User prompt for the perfection audit, including the source code to analyze.
#[must_use]
pub fn user_prompt_for_perfection(all_code: &str) -> String {
    format!(
        "Analyze the following Swift source code for quality across 9 axes:\n\n\
         {all_code}\n\n\
         Return the 9-axis audit as a JSON array.",
        all_code = all_code,
    )
}

/// System prompt for generating App Store Connect metadata.
#[must_use]
pub fn system_prompt_for_asc_metadata() -> String {
    "You are an App Store optimization expert. Given the Swift source code and app \
     specification, generate complete App Store Connect metadata. \
     Output ONLY a JSON object with these exact keys:\n\
     - name: string (30 chars max)\n\
     - subtitle: string (30 chars max)\n\
     - primary_category: string (App Store category)\n\
     - keywords: array of strings (max 100 chars total comma-separated)\n\
     - description: string (4000 chars max, compelling app description)\n\
     - promotional_text: string (170 chars max)\n\
     - support_url: string (URL)\n\
     - marketing_url: string (URL, or empty string)\n\
     - age_rating: string (e.g. \"4+\")\n\
     - privacy_policy_url: string (URL)\n\n\
     No prose, no markdown — just the JSON object.".to_string()
}

/// User prompt for ASC metadata generation.
#[must_use]
pub fn user_prompt_for_asc_metadata(request: &BuildRequest, all_code: &str) -> String {
    // Truncate code to avoid exceeding context limits
    let code_preview = if all_code.len() > 8000 {
        &all_code[..8000]
    } else {
        all_code
    };

    format!(
        "Generate App Store Connect metadata for this app:\n\n\
         **App Title:** {title}\n\
         **Description:** {prompt}\n\
         **Category:** {category}\n\
         **Style:** {style}\n\n\
         Here is the source code:\n\n\
         {code_preview}\n\n\
         Return the metadata as a JSON object.",
        title = request.title,
        prompt = request.prompt,
        category = request.category,
        style = request.style,
        code_preview = code_preview,
    )
}

/// Sanitize an app name for use as a Swift module/identifier.
fn sanitize_module_name(name: &str) -> String {
    let words: Vec<&str> = name.split_whitespace().collect();
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