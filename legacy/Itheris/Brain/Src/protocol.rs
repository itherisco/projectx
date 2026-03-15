use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize)]
pub enum Identity {
    JuliaReasoner,
    PythonExplorer,
    Human,
    ToolExecutor,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum MessageType {
    SenseReport,
    WorldState,
    Proposal,
    Decision,
    ActionRequest,
    ActionApproval,
    ActionResult,
    AuditLog,
    StatusRequest,
    StatusResponse,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Envelope {
    pub id: Uuid,
    pub timestamp: DateTime<Utc>,
    pub sender: Identity,
    pub recipient: Identity,
    pub msg_type: MessageType,
    pub payload: serde_json::Value,
}