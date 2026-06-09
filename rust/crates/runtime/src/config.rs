pub struct ConfigEntry { pub key: String, pub value: String }
pub enum ConfigError { NotFound }
pub struct ConfigLoader;
pub enum ConfigSource { File }
pub struct McpConfigCollection { pub servers: Vec<McpServerConfig> }
pub struct McpManagedProxyServerConfig { pub name: String }
pub struct McpOAuthConfig { pub client_id: String }
pub struct McpRemoteServerConfig { pub url: String }
pub struct McpSdkServerConfig { pub name: String }
pub struct McpServerConfig { pub name: String }
pub struct McpStdioServerConfig { pub command: String }
pub enum McpTransport { Stdio }
pub struct McpWebSocketServerConfig { pub url: String }
pub struct OAuthConfig { pub client_id: String }
pub struct ProviderFallbackConfig { pub models: Vec<String> }
pub struct ResolvedPermissionMode;
pub struct RuntimeConfig { pub mcp_servers: Vec<McpServerConfig> }
pub struct RuntimeFeatureConfig { pub features: Vec<String> }
pub struct RuntimeHookConfig { pub hooks: Vec<String> }
pub struct RuntimePermissionRuleConfig { pub rules: Vec<String> }
pub struct RuntimePluginConfig { pub plugins: Vec<String> }
pub struct ScopedMcpServerConfig { pub name: String }
pub const CLAW_SETTINGS_SCHEMA_NAME: &str = "claw-settings";
