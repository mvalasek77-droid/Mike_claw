pub fn auto_compaction_threshold_from_env() -> Option<usize> { None }
pub struct ApiClient;
pub struct ApiRequest { pub model: String }
pub enum AssistantEvent { Text(String) }
pub enum AutoCompactionEvent { Compacted }
pub struct ConversationRuntime;
pub struct PromptCacheEvent;
pub enum RuntimeError { Api(String) }
pub struct StaticToolExecutor;
pub type ToolError = String;
pub trait ToolExecutor { fn execute(&self, tool: &str, input: &str) -> Result<String, ToolError>; }
pub struct TurnSummary { pub tokens: usize }
