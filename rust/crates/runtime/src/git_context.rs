pub struct GitCommitEntry { pub hash: String, pub message: String }
pub struct GitContext { pub commits: Vec<GitCommitEntry> }
