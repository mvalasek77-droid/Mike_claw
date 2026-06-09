pub fn mcp_server_signature(_name: &str) -> String { String::new() }
pub fn mcp_tool_name(_server: &str, _tool: &str) -> String { format!("{}_{}", _server, _tool) }
pub fn mcp_tool_prefix(_server: &str) -> String { _server.to_string() }
pub fn normalize_name_for_mcp(_name: &str) -> String { _name.to_string() }
pub fn scoped_mcp_config_hash(_name: &str) -> String { String::new() }
pub fn unwrap_ccr_proxy_url(_url: &Option<String>) -> Option<String> { None }
