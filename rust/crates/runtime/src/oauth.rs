pub fn clear_oauth_credentials(_name: &str) {}
pub fn code_challenge_s256(_verifier: &str) -> String { String::new() }
pub fn credentials_path(_name: &str) -> std::path::PathBuf { std::path::PathBuf::new() }
pub fn generate_pkce_pair() -> (String, String) { (String::new(), String::new()) }
pub fn generate_state() -> String { String::new() }
pub fn load_oauth_credentials(_name: &str) -> Option<OAuthTokenSet> { None }
pub fn loopback_redirect_uri(_port: u16) -> String { String::new() }
pub fn parse_oauth_callback_query(_query: &str) -> Result<OAuthCallbackParams, String> { Err("stub".into()) }
pub fn parse_oauth_callback_request_target(_target: &str) -> Result<OAuthCallbackParams, String> { Err("stub".into()) }
pub fn save_oauth_credentials(_name: &str, _tokens: &OAuthTokenSet) -> Result<(), String> { Ok(()) }
pub struct OAuthAuthorizationRequest;
pub struct OAuthCallbackParams;
pub struct OAuthRefreshRequest;
pub struct OAuthTokenExchangeRequest;
pub struct OAuthTokenSet { pub access_token: String, pub refresh_token: String }
pub enum PkceChallengeMethod { S256 }
pub struct PkceCodePair { pub verifier: String, pub challenge: String }
