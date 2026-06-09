//! Project scaffold helpers for the builder.
//!
//! Creates the on-disk project structure for a generated iOS app under
//! `~/CodeGenie/Projects/{sanitized_app_name}/`.

use crate::builder::BuildRequest;
use std::fs;
use std::path::PathBuf;

/// Decide where on the local filesystem a generated project should live.
///
/// Uses `~/CodeGenie/Projects/{sanitized_app_name}/` so projects are
/// easy to find by name rather than by UUID.
#[must_use]
pub fn project_path_for(request: &BuildRequest) -> PathBuf {
    let sanitized = sanitize_app_name(&request.title);
    let mut base = dirs_home();
    base.push("CodeGenie");
    base.push("Projects");
    base.push(&sanitized);
    base
}

/// Create the initial project directory structure for a `SwiftUI` iOS app.
///
/// This writes:
/// - `Package.swift` with a `SwiftUI` app target
/// - `Sources/{AppName}/` with an `@main` App entry point
/// - `Sources/{AppName}/ContentView.swift` with a placeholder view
///
/// Returns the project root `PathBuf` on success.
pub fn scaffold_project(request: &BuildRequest) -> Result<PathBuf, String> {
    let project_path = project_path_for(request);
    let app_name = sanitize_app_name(&request.title);
    let module_name = sanitize_module_name(&request.title);

    // Create the project root
    fs::create_dir_all(&project_path).map_err(|e| format!("Failed to create project dir: {e}"))?;

    // Create Sources/{ModuleName}/ directory
    let sources_dir = project_path.join("Sources").join(&module_name);
    fs::create_dir_all(&sources_dir).map_err(|e| format!("Failed to create Sources dir: {e}"))?;

    // Write Package.swift
    let package_swift = generate_package_swift(&app_name, &module_name, &request.target_ios);
    fs::write(project_path.join("Package.swift"), &package_swift)
        .map_err(|e| format!("Failed to write Package.swift: {e}"))?;

    // Write App entry point
    let app_file = generate_app_file(&module_name);
    fs::write(
        sources_dir.join(format!("{module_name}App.swift")),
        &app_file,
    )
    .map_err(|e| format!("Failed to write App file: {e}"))?;

    // Write placeholder ContentView
    let content_view = generate_content_view();
    fs::write(sources_dir.join("ContentView.swift"), &content_view)
        .map_err(|e| format!("Failed to write ContentView.swift: {e}"))?;

    // Write a placeholder Assets.xcassets directory for completeness
    let assets_dir = sources_dir.join("Assets.xcassets");
    fs::create_dir_all(&assets_dir).map_err(|e| format!("Failed to create Assets.xcassets: {e}"))?;
    let contents_json = r#"{"info":{"version":1,"author":"xcode"}}"#;
    fs::write(assets_dir.join("Contents.json"), contents_json)
        .map_err(|e| format!("Failed to write Assets Contents.json: {e}"))?;

    Ok(project_path)
}

/// Sanitize an app name for use as a filesystem directory component.
///
/// Keeps alphanumeric chars, spaces become hyphens, strips everything else,
/// then lowercases.
fn sanitize_app_name(name: &str) -> String {
    name.replace(' ', "-")
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-')
        .collect::<String>()
        .to_lowercase()
}

/// Sanitize an app name for use as a Swift module/identifier.
///
/// `PascalCase`, alphanumeric only. Must start with an uppercase letter.
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
    // Strip non-alphanumeric
    let clean: String = pascal.chars().filter(|c| c.is_alphanumeric()).collect();
    // Ensure it starts with a letter
    if clean.is_empty() {
        return "CodeGenieApp".to_string();
    }
    if clean.chars().next().is_none_or(|c| c.is_ascii_digit()) {
        format!("App{clean}")
    } else {
        clean
    }
}

fn generate_package_swift(app_name: &str, module_name: &str, target_ios: &str) -> String {
    let ios_version = target_ios.replace('.', "");
    format!(
        r#"// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{app_name}",
    platforms: [.iOS(.v{ios_version})],
    products: [
        .executable(
            name: "{app_name}",
            targets: ["{module_name}"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "{module_name}",
            path: "Sources/{module_name}"
        ),
    ]
)
"#
    )
}

fn generate_app_file(module_name: &str) -> String {
    format!(
        r#"import SwiftUI

@main
struct {module_name}App: App {{
    var body: some Scene {{
        WindowGroup {{
            ContentView()
        }}
    }}
}}
"#
    )
}

fn generate_content_view() -> String {
    r#"import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello, CodeGenie!")
                .font(.title)
                .padding()
        }
    }
}

#Preview {
    ContentView()
}
"#
    .to_string()
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME").map_or_else(|_| PathBuf::from("/tmp"), PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_app_name() {
        assert_eq!(sanitize_app_name("My Cool App"), "my-cool-app");
        assert_eq!(sanitize_app_name("Hello! World?"), "hello-world");
        assert_eq!(sanitize_app_name("TaskMaster3000"), "taskmaster3000");
    }

    #[test]
    fn test_sanitize_module_name() {
        assert_eq!(sanitize_module_name("My Cool App"), "MyCoolApp");
        assert_eq!(sanitize_module_name("task tracker"), "TaskTracker");
        assert_eq!(sanitize_module_name("123go"), "App123go");
        assert_eq!(sanitize_module_name(""), "CodeGenieApp");
    }
}