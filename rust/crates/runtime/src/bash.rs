pub fn execute_bash(_input: BashCommandInput) -> Result<BashCommandOutput, String> { Err("stub".into()) }
pub struct BashCommandInput { pub command: String }
pub struct BashCommandOutput { pub stdout: String, pub stderr: String, pub exit_code: i32 }
