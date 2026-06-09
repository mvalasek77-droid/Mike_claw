pub const MCP_SERVER_PROTOCOL_VERSION: &str = "2024-11-05";
pub struct McpServer;
pub struct McpServerSpec { pub name: String }
pub trait ToolCallHandler { fn call(&self, tool: &str, input: &str) -> Result<String, String>; }
