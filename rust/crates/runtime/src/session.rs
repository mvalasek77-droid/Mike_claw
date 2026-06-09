pub enum ContentBlock { Text(String) }
pub struct ConversationMessage { pub role: MessageRole, pub content: Vec<ContentBlock> }
pub enum MessageRole { User, Assistant }
pub struct Session { pub id: String }
pub struct SessionCompaction;
pub enum SessionError { NotFound }
pub struct SessionFork;
pub struct SessionPromptEntry;
