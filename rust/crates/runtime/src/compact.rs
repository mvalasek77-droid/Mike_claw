pub fn compact_session(_s: &str) -> CompactionResult { CompactionResult { summary: String::new(), tokens_saved: 0 } }
pub fn estimate_session_tokens(_s: &str) -> usize { 0 }
pub fn format_compact_summary(_s: &str) -> String { String::new() }
pub fn get_compact_continuation_message() -> String { String::new() }
pub fn should_compact(_tokens: usize, _limit: usize) -> bool { false }
pub struct CompactionConfig { pub max_tokens: usize }
pub struct CompactionResult { pub summary: String, pub tokens_saved: usize }
