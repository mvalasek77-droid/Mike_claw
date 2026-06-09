pub fn compute_event_fingerprint(_event: &LaneEvent) -> String { String::new() }
pub fn dedupe_superseded_commit_events(_events: &[LaneEvent]) -> Vec<LaneEvent> { vec![] }
pub fn dedupe_terminal_events(_events: &[LaneEvent]) -> Vec<LaneEvent> { vec![] }
pub fn is_terminal_event(_event: &LaneEvent) -> bool { false }
pub struct BlockedSubphase;
pub struct EventProvenance;
pub struct LaneCommitProvenance;
pub struct LaneEvent { pub name: LaneEventName }
pub struct LaneEventBlocker;
pub struct LaneEventBuilder;
pub struct LaneEventMetadata;
pub enum LaneEventName { Commit }
pub enum LaneEventStatus { Pending }
pub enum LaneFailureClass { Network }
pub struct LaneOwnership;
pub struct SessionIdentity { pub id: String }
pub enum ShipMergeMethod { Squash }
pub struct ShipProvenance;
pub enum WatcherAction { Ignore }
