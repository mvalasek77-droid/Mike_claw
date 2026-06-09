pub fn build_linux_sandbox_command(_cmd: &str) -> LinuxSandboxCommand { LinuxSandboxCommand { program: _cmd.to_string() } }
pub fn detect_container_environment() -> ContainerEnvironment { ContainerEnvironment::None }
pub fn detect_container_environment_from(_path: &str) -> ContainerEnvironment { ContainerEnvironment::None }
pub fn resolve_sandbox_status() -> SandboxStatus { SandboxStatus::Uncontained }
pub fn resolve_sandbox_status_for_request(_req: &SandboxRequest) -> SandboxStatus { SandboxStatus::Uncontained }
pub enum ContainerEnvironment { None, Docker }
pub enum FilesystemIsolationMode { None }
pub struct LinuxSandboxCommand { pub program: String }
pub struct SandboxConfig;
pub struct SandboxDetectionInputs;
pub struct SandboxRequest;
pub enum SandboxStatus { Uncontained }
