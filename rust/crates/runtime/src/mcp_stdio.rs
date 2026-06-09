pub fn spawn_mcp_stdio_process(_cmd: &str, _args: &[&str]) -> Result<McpStdioProcess, String> { Err("stub".into()) }
pub struct JsonRpcError { pub message: String }
pub type JsonRpcId = Option<serde_json::Value>;
pub struct JsonRpcRequest { pub id: JsonRpcId }
pub struct JsonRpcResponse { pub id: JsonRpcId }
pub struct ManagedMcpTool { pub name: String }
pub struct McpDiscoveryFailure;
pub struct McpInitializeClientInfo;
pub struct McpInitializeParams;
pub struct McpInitializeResult;
pub struct McpInitializeServerInfo;
pub struct McpListResourcesParams;
pub struct McpListResourcesResult;
pub struct McpReadResourceParams;
pub struct McpReadResourceResult;
pub struct McpResource { pub uri: String }
pub struct McpResourceContents;
pub struct McpServerManager;
pub enum McpServerManagerError { ConnectionFailed }
pub struct McpStdioProcess;
pub struct McpTool { pub name: String }
pub struct McpToolCallContent;
pub struct McpToolCallParams;
pub struct McpToolCallResult;
pub struct McpToolDiscoveryReport;
pub struct UnsupportedMcpServer;
pub struct McpListToolsParams;
pub struct McpListToolsResult;
