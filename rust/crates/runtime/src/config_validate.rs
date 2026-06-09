pub fn check_unsupported_format(_path: &str) -> Vec<ConfigDiagnostic> { vec![] }
pub fn format_diagnostics(_diags: &[ConfigDiagnostic]) -> String { String::new() }
pub fn validate_config_file(_path: &str) -> ValidationResult { ValidationResult::Valid }
pub struct ConfigDiagnostic { pub message: String }
pub enum DiagnosticKind { Warning }
pub enum ValidationResult { Valid, Invalid }
