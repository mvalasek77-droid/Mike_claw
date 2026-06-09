pub fn edit_file(_path: &str, _content: &str) -> Result<EditFileOutput, String> { Err("stub".into()) }
pub fn glob_search(_pattern: &str) -> Result<GlobSearchOutput, String> { Err("stub".into()) }
pub fn grep_search(_input: GrepSearchInput) -> Result<GrepSearchOutput, String> { Err("stub".into()) }
pub fn read_file(_path: &str) -> Result<ReadFileOutput, String> { Err("stub".into()) }
pub fn write_file(_path: &str, _content: &str) -> Result<WriteFileOutput, String> { Err("stub".into()) }
pub struct EditFileOutput { pub path: String }
pub struct GlobSearchOutput { pub files: Vec<String> }
pub struct GrepSearchInput { pub pattern: String, pub path: String }
pub struct GrepSearchOutput { pub matches: Vec<String> }
pub struct ReadFileOutput { pub content: String }
pub struct StructuredPatchHunk { pub old: String, pub new: String }
pub struct TextFilePayload { pub path: String, pub content: String }
pub struct WriteFileOutput { pub path: String }
