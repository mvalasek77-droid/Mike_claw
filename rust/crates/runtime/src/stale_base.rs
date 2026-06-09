pub fn check_base_commit(_path: &str) -> Result<BaseCommitState, String> { Err("stub".into()) }
pub fn format_stale_base_warning(_state: &BaseCommitState) -> String { String::new() }
pub fn read_claw_base_file(_path: &str) -> Option<String> { None }
pub fn resolve_expected_base(_path: &str) -> Option<String> { None }
pub enum BaseCommitSource { Remote }
pub struct BaseCommitState;
