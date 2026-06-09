pub fn load_system_prompt() -> Result<String, PromptBuildError> { Ok(String::new()) }
pub fn prepend_bullets(_text: &str, _items: &[String]) -> String { _text.to_string() }
pub struct ContextFile { pub path: String }
pub struct ProjectContext { pub files: Vec<ContextFile> }
pub enum PromptBuildError { NotFound }
pub struct SystemPromptBuilder;
pub const FRONTIER_MODEL_NAME: &str = "claude-sonnet-4-20250514";
pub const SYSTEM_PROMPT_DYNAMIC_BOUNDARY: &str = "";
