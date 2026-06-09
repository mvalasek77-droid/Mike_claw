use std::sync::RwLock;
pub struct SessionStore { sessions: RwLock<Vec<String>> }
