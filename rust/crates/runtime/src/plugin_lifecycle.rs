pub enum DegradedMode { Fallback }
pub struct DiscoveryResult;
pub struct PluginHealthcheck;
pub struct PluginLifecycle;
pub enum PluginLifecycleEvent { Discovered }
pub enum PluginState { Running }
pub struct ResourceInfo;
pub struct ServerHealth;
pub enum ServerStatus { Running }
pub struct ToolInfo { pub name: String }
