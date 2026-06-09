//! Prompt templates used by the builder orchestrator.
//!
//! These prompts instruct the AI to generate Swift files for an iOS app
//! in the form of a JSON array of `{path, content}` objects.

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