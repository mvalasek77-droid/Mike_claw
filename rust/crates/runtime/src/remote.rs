pub fn inherited_upstream_proxy_env() -> Vec<(String, String)> { vec![] }
pub fn no_proxy_list() -> Vec<String> { vec![] }
pub fn read_token() -> Option<String> { None }
pub fn upstream_proxy_ws_url() -> Option<String> { None }
pub struct RemoteSessionContext;
pub struct UpstreamProxyBootstrap;
pub enum UpstreamProxyState { Disconnected }
pub const DEFAULT_REMOTE_BASE_URL: &str = "";
pub const DEFAULT_SESSION_TOKEN_PATH: &str = "";
pub const DEFAULT_SYSTEM_CA_BUNDLE: &str = "";
pub const NO_PROXY_HOSTS: &[&str] = &[];
pub const UPSTREAM_PROXY_ENV_KEYS: &[&str] = &[];
