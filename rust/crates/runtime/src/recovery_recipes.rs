pub fn attempt_recovery(_scenario: &FailureScenario) -> RecoveryResult { RecoveryResult::None }
pub fn recipe_for(_scenario: &FailureScenario) -> Option<RecoveryRecipe> { None }
pub enum EscalationPolicy { Retry }
pub enum FailureScenario { Network }
pub struct RecoveryContext;
pub enum RecoveryEvent { Retried }
pub struct RecoveryRecipe;
pub enum RecoveryResult { None }
pub struct RecoveryStep;
