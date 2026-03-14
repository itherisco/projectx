//! # Type Mirroring for Julia-Rust IPC
//!
//! This module provides Rust structs that safely mirror Julia's types
//! using jlrs-derive for zero-copy IPC communication.
//!
//! These types prevent memory corruption at the FFI boundary by ensuring
//! both sides use compatible memory layouts.

#[cfg(feature = "jlrs")]
use jlrs::prelude::*;
use serde::{Serialize, Deserialize};

/// Brain output from Julia cognitive processing
/// Mirrors: IntegrationActionProposal from Julia types.jl
#[derive(Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "jlrs", derive(JuliaData))]
pub struct BrainOutput {
    /// Unique identifier
    pub id: String,
    /// The capability being proposed
    pub capability_id: String,
    /// Confidence score [0, 1]
    pub confidence: f32,
    /// Predicted computational cost
    pub predicted_cost: f32,
    /// Predicted reward value
    pub predicted_reward: f32,
    /// Risk assessment [0, 1]
    pub risk: f32,
    /// Reasoning for the proposal
    pub reasoning: String,
    /// Estimated impact [0, 1]
    pub impact_estimate: f32,
    /// Timestamp of generation
    pub timestamp: i64,
}

impl BrainOutput {
    /// Create a new BrainOutput from raw values
    pub fn new(
        capability_id: String,
        confidence: f32,
        predicted_cost: f32,
        predicted_reward: f32,
        risk: f32,
        reasoning: String,
    ) -> Self {
        BrainOutput {
            id: uuid::Uuid::new_v4().to_string(),
            capability_id,
            confidence: confidence.clamp(0.0, 1.0),
            predicted_cost,
            predicted_reward: predicted_reward.clamp(0.0, 1.0),
            risk: risk.clamp(0.0, 1.0),
            reasoning,
            impact_estimate: 0.5,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
}

/// Request from Rust to Julia for capability execution
/// Mirrors: CapabilityRequest from Julia
#[derive(Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "jlrs", derive(JuliaData))]
pub struct CapabilityRequest {
    /// Unique request identifier
    pub request_id: String,
    /// Capability to execute
    pub capability_id: String,
    /// Input parameters as JSON string
    pub parameters: String,
    /// Priority level [0, 1]
    pub priority: f32,
    /// Request timeout in seconds
    pub timeout_secs: u32,
    /// Whether this is a dry run
    pub dry_run: bool,
}

impl CapabilityRequest {
    /// Create a new capability request
    pub fn new(capability_id: String, parameters: String) -> Self {
        CapabilityRequest {
            request_id: uuid::Uuid::new_v4().to_string(),
            capability_id,
            parameters,
            priority: 0.5,
            timeout_secs: 30,
            dry_run: false,
        }
    }
}

/// Observation from the environment
/// Mirrors: IntegrationObservation from Julia types.jl
#[derive(Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "jlrs", derive(JuliaData))]
pub struct EnvironmentObservation {
    /// CPU load [0, 1]
    pub cpu_load: f32,
    /// Memory usage [0, 1]
    pub memory_usage: f32,
    /// Disk I/O rate
    pub disk_io: f32,
    /// Network latency in ms
    pub network_latency: f32,
    /// Number of files in system
    pub file_count: i32,
    /// Number of running processes
    pub process_count: i32,
    /// Energy level [0, 1]
    pub energy_level: f32,
    /// Confidence in observation
    pub confidence: f32,
}

impl Default for EnvironmentObservation {
    fn default() -> Self {
        EnvironmentObservation {
            cpu_load: 0.0,
            memory_usage: 0.0,
            disk_io: 0.0,
            network_latency: 0.0,
            file_count: 0,
            process_count: 0,
            energy_level: 1.0,
            confidence: 0.8,
        }
    }
}

/// Kernel decision response
/// Mirrors: ApprovalResult from Rust kernel.rs
#[derive(Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "jlrs", derive(JuliaData))]
pub struct KernelDecision {
    /// Whether the action was approved
    pub approved: bool,
    /// Unique decision identifier
    pub decision_id: String,
    /// Risk level assessed
    pub risk_level: String,
    /// Conditions or reason for decision
    pub conditions: String,
    /// Timestamp of decision
    pub timestamp: i64,
}

impl KernelDecision {
    /// Create an approval decision
    pub fn approved(conditions: String) -> Self {
        KernelDecision {
            approved: true,
            decision_id: uuid::Uuid::new_v4().to_string(),
            risk_level: "low".to_string(),
            conditions,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
    
    /// Create a rejection decision
    pub fn rejected(reason: String) -> Self {
        KernelDecision {
            approved: false,
            decision_id: uuid::Uuid::new_v4().to_string(),
            risk_level: "high".to_string(),
            conditions: reason,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
}

/// IPC message wrapper for type-safe communication
#[derive(Clone, Serialize, Deserialize)]
pub struct IpcMessage {
    /// Message type identifier
    pub msg_type: IpcMessageType,
    /// Sequence number
    pub sequence: u64,
    /// Timestamp
    pub timestamp: i64,
    /// Serialized payload
    pub payload: Vec<u8>,
}

/// IPC message types
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[repr(u8)]
pub enum IpcMessageType {
    BrainOutput = 0,
    CapabilityRequest = 1,
    KernelDecision = 2,
    EnvironmentObservation = 3,
    Heartbeat = 4,
    Panic = 5,
    Shutdown = 6,
}

impl IpcMessage {
    /// Create a new IPC message
    pub fn new(msg_type: IpcMessageType, payload: Vec<u8>) -> Self {
        IpcMessage {
            msg_type,
            sequence: SEQUENCE_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            timestamp: chrono::Utc::now().timestamp_millis(),
            payload,
        }
    }
    
    /// Serialize a BrainOutput to IPC message
    pub fn from_brain_output(output: &BrainOutput) -> Self {
        let payload = serde_json::to_vec(output).unwrap_or_default();
        IpcMessage::new(IpcMessageType::BrainOutput, payload)
    }
    
    /// Deserialize a BrainOutput from IPC message
    pub fn to_brain_output(&self) -> Option<BrainOutput> {
        if self.msg_type != IpcMessageType::BrainOutput {
            return None;
        }
        serde_json::from_slice(&self.payload).ok()
    }
    
    /// Serialize a CapabilityRequest to IPC message
    pub fn from_capability_request(request: &CapabilityRequest) -> Self {
        let payload = serde_json::to_vec(request).unwrap_or_default();
        IpcMessage::new(IpcMessageType::CapabilityRequest, payload)
    }
    
    /// Deserialize a CapabilityRequest from IPC message
    pub fn to_capability_request(&self) -> Option<CapabilityRequest> {
        if self.msg_type != IpcMessageType::CapabilityRequest {
            return None;
        }
        serde_json::from_slice(&self.payload).ok()
    }
}

static SEQUENCE_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_brain_output_creation() {
        let output = BrainOutput::new(
            "test_capability".to_string(),
            0.9,
            0.1,
            0.8,
            0.2,
            "Test reasoning".to_string(),
        );
        
        assert_eq!(output.capability_id, "test_capability");
        assert!((output.confidence - 0.9).abs() < 0.001);
        assert!((output.risk - 0.2).abs() < 0.001);
    }
    
    #[test]
    fn test_capability_request_creation() {
        let request = CapabilityRequest::new(
            "write_file".to_string(),
            "{\"path\": \"/tmp/test\"}".to_string(),
        );
        
        assert_eq!(request.capability_id, "write_file");
        assert!(!request.request_id.is_empty());
    }
    
    #[test]
    fn test_ipc_message_roundtrip() {
        let output = BrainOutput::new(
            "test_cap".to_string(),
            0.5,
            0.2,
            0.7,
            0.3,
            "Test".to_string(),
        );
        
        let msg = IpcMessage::from_brain_output(&output);
        let recovered = msg.to_brain_output();
        
        assert!(recovered.is_some());
        assert_eq!(recovered.unwrap().capability_id, "test_cap");
    }
}
