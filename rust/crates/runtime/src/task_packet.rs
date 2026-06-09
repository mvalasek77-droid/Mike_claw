pub fn validate_packet(_data: &[u8]) -> Result<ValidatedPacket, TaskPacketValidationError> { Err(TaskPacketValidationError) }
pub struct TaskPacket;
pub struct TaskPacketValidationError;
pub struct ValidatedPacket;
