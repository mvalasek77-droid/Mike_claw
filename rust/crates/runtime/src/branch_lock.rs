pub fn detect_branch_lock_collisions(_intent: BranchLockIntent) -> Result<Vec<BranchLockCollision>, String> { Ok(vec![]) }
pub struct BranchLockCollision { pub path: String }
pub struct BranchLockIntent { pub path: String }
