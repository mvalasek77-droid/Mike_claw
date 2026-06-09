pub fn apply_policy(_freshness: &BranchFreshness) -> StaleBranchAction { StaleBranchAction::None }
pub fn check_freshness(_branch: &str) -> BranchFreshness { BranchFreshness::Fresh }
pub enum BranchFreshness { Fresh, Stale }
pub enum StaleBranchAction { None, Rebase }
pub struct StaleBranchEvent;
pub struct StaleBranchPolicy;
