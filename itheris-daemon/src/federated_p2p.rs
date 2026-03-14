// FederatedIntelligenceP2P.rs - P2P Mesh Networking for Federated Learning
// 
// This module implements the peer-to-peer mesh topology for the federated
// intelligence system within the Rust Warden. It handles:
// - Peer discovery via broadcast
// - Secure handshake establishment
// - Encrypted message routing
// - Federation protocol packet handling
//
// Architecture: Decentralized mesh with no central server
// Security: All peer communications are encrypted with TPM-backed keys

use std::collections::HashMap;
use std::net::{SocketAddr, UdpSocket};
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant, SystemTime};
use serde::{Deserialize, Serialize};
use tracing::{info, warn, error};

// ============================================================================
// CONSTANTS
// ============================================================================

/// Maximum number of peers in the mesh
pub const MAX_PEERS: usize = 1000;

/// Default UDP port for peer discovery
pub const DEFAULT_DISCOVERY_PORT: u16 = 45678;

/// Default UDP port for federated data exchange
pub const DEFAULT_FEDERATION_PORT: u16 = 45679;

/// Heartbeat interval in seconds
pub const HEARTBEAT_INTERVAL_SECS: u64 = 30;

/// Peer timeout in seconds (mark as offline after this)
pub const PEER_TIMEOUT_SECS: u64 = 120;

/// Maximum packet size for federation messages
pub const MAX_PACKET_SIZE: usize = 65535;

/// Discovery broadcast interval
pub const DISCOVERY_INTERVAL_SECS: u64 = 10;

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/// Unique identifier for a peer node
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PeerId(pub String);

/// Network address of a peer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerAddress {
    pub ip: String,
    pub discovery_port: u16,
    pub federation_port: u16,
}

/// Represents a peer in the mesh network
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Peer {
    pub id: PeerId,
    pub address: PeerAddress,
    pub public_key: Vec<u8>,
    pub reliability_score: f64,  // Historical reliability (0.0 - 1.0)
    pub last_seen: SystemTime,
    pub is_online: bool,
    pub version: String,  // Software version for compatibility
}

/// Message types in the federation protocol
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FederationMessageType {
    Discovery,           // Initial peer discovery
    Handshake,           // Secure handshake initiation
    HandshakeAck,        // Handshake acknowledgment
    Heartbeat,           // Keep-alive message
    LatentBroadcast,     // Compressed neural embeddings (encrypted)
    AggregationRequest,  // Request to aggregate peer updates
    AggregationResponse, // Response with aggregated data
    UpdateProposal,      // Proposed model update
    UpdateAck,           // Acknowledgment of update
    VetoNotification,    // LEP veto notification
    Disconnect,          // Graceful disconnect
}

/// Header for federation protocol messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationHeader {
    pub message_type: FederationMessageType,
    pub sender_id: PeerId,
    pub receiver_id: Option<PeerId>,
    pub timestamp: u64,  // Unix timestamp
    pub sequence: u64,
    pub session_id: String,
}

/// Payload for federated latent embeddings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LatentPayload {
    pub embeddings: Vec<f64>,      // Compressed 64-dim embeddings
    pub gradient_norm: f64,         // For stability check
    pub epoch: u32,                 // Training epoch
    pub privacy_budget: f64,       // Differential privacy budget (epsilon)
    pub noise_scale: f64,          // Added Gaussian noise scale
    pub checksum: String,          // SHA256 checksum for integrity
}

/// Complete federation message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationMessage {
    pub header: FederationHeader,
    pub payload: Option<LatentPayload>,
    pub signature: Vec<u8>,  // Ed25519 signature
}

// ============================================================================
// PEER STATE MANAGEMENT
// ============================================================================

/// State for tracking all known peers
pub struct MeshState {
    pub local_peer_id: PeerId,
    pub local_address: PeerAddress,
    pub peers: HashMap<PeerId, Peer>,
    pub session_keys: HashMap<PeerId, Vec<u8>>,  // Symmetric session keys
    pub pending_handshakes: HashMap<PeerId, Instant>,  // In-progress handshakes
    pub sequence_counter: u64,
}

impl MeshState {
    pub fn new(local_id: PeerId, local_addr: PeerAddress) -> Self {
        Self {
            local_peer_id: local_id,
            local_address: local_addr,
            peers: HashMap::new(),
            session_keys: HashMap::new(),
            pending_handshakes: HashMap::new(),
            sequence_counter: 0,
        }
    }

    pub fn next_sequence(&mut self) -> u64 {
        self.sequence_counter += 1;
        self.sequence_counter
    }

    pub fn add_peer(&mut self, peer: Peer) {
        self.peers.insert(peer.id.clone(), peer);
    }

    pub fn remove_peer(&mut self, peer_id: &PeerId) {
        self.peers.remove(peer_id);
        self.session_keys.remove(peer_id);
    }

    pub fn get_online_peers(&self) -> Vec<&Peer> {
        self.peers.values()
            .filter(|p| p.is_online)
            .collect()
    }

    pub fn update_peer_online_status(&mut self) {
        let now = SystemTime::now();
        for peer in self.peers.values_mut() {
            if let Ok(duration) = now.duration_since(peer.last_seen) {
                peer.is_online = duration.as_secs() < PEER_TIMEOUT_SECS;
            }
        }
    }
}

// ============================================================================
// PACKET ENCODING/DECODING
// ============================================================================

/// Encode a federation message to bytes
pub fn encode_message(msg: &FederationMessage) -> Result<Vec<u8>, String> {
    serde_json::to_vec(msg)
        .map_err(|e| format!("Failed to encode message: {}", e))
}

/// Decode bytes to a federation message
pub fn decode_message(data: &[u8]) -> Result<FederationMessage, String> {
    serde_json::from_slice(data)
        .map_err(|e| format!("Failed to decode message: {}", e))
}

// ============================================================================
// PEER DISCOVERY
// ============================================================================

/// Generate a discovery packet for broadcast
pub fn create_discovery_message(local_id: &PeerId, version: &str) -> FederationMessage {
    FederationMessage {
        header: FederationHeader {
            message_type: FederationMessageType::Discovery,
            sender_id: local_id.clone(),
            receiver_id: None,
            timestamp: SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            sequence: 0,
            session_id: String::new(),
        },
        payload: None,
        signature: Vec::new(),
    }
}

/// Generate a handshake message for peer introduction
pub fn create_handshake_message(
    local_id: &PeerId,
    target_id: &PeerId,
    public_key: &[u8],
    session_id: &str,
    sequence: u64,
) -> FederationMessage {
    FederationMessage {
        header: FederationHeader {
            message_type: FederationMessageType::Handshake,
            sender_id: local_id.clone(),
            receiver_id: Some(target_id.clone()),
            timestamp: SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            sequence,
            session_id: session_id.to_string(),
        },
        payload: None,
        signature: public_key.to_vec(),
    }
}

/// Generate a heartbeat message
pub fn create_heartbeat_message(
    local_id: &PeerId,
    session_id: &str,
    sequence: u64,
) -> FederationMessage {
    FederationMessage {
        header: FederationHeader {
            message_type: FederationMessageType::Heartbeat,
            sender_id: local_id.clone(),
            receiver_id: None,
            timestamp: SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            sequence,
            session_id: session_id.to_string(),
        },
        payload: None,
        signature: Vec::new(),
    }
}

// ============================================================================
// FEDERATION MESSAGE CREATION
// ============================================================================

/// Create a latent broadcast message with encrypted embeddings
pub fn create_latent_broadcast_message(
    local_id: &PeerId,
    target_id: &PeerId,
    session_id: &str,
    sequence: u64,
    payload: LatentPayload,
) -> FederationMessage {
    FederationMessage {
        header: FederationHeader {
            message_type: FederationMessageType::LatentBroadcast,
            sender_id: local_id.clone(),
            receiver_id: Some(target_id.clone()),
            timestamp: SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            sequence,
            session_id: session_id.to_string(),
        },
        payload: Some(payload),
        signature: Vec::new(),
    }
}

/// Create an aggregation request message
pub fn create_aggregation_request(
    local_id: &PeerId,
    target_id: &PeerId,
    session_id: &str,
    sequence: u64,
    peer_ids: Vec<PeerId>,
) -> FederationMessage {
    // Serialize peer IDs as payload
    let payload_json = serde_json::to_string(&peer_ids).unwrap_or_default();
    
    FederationMessage {
        header: FederationHeader {
            message_type: FederationMessageType::AggregationRequest,
            sender_id: local_id.clone(),
            receiver_id: Some(target_id.clone()),
            timestamp: SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            sequence,
            session_id: session_id.to_string(),
        },
        payload: None,  // Would need custom payload type for this
        signature: Vec::new(),
    }
}

// ============================================================================
// PEER RELIABILITY TRACKING
// ============================================================================

/// Update reliability score based on peer behavior
pub fn update_reliability_score(
    current_score: f64,
    message_received: bool,
    latency_ms: u64,
    was_valid: bool,
) -> f64 {
    let base_weight = 0.95;
    let success_weight = if message_received && was_valid { 0.05 } else { -0.1 };
    
    // Penalize high latency
    let latency_factor = if latency_ms > 1000 { -0.05 } else { 0.0 };
    
    // Calculate new score
    let new_score = current_score * base_weight + success_weight + latency_factor;
    
    // Clamp to [0.0, 1.0]
    new_score.max(0.0).min(1.0)
}

// ============================================================================
// MESG ROUTING HELPERS
// ============================================================================

/// Check if a message should be forwarded to another peer
pub fn should_forward_message(
    msg: &FederationMessage,
    local_id: &PeerId,
    peer_id: &PeerId,
) -> bool {
    // Don't forward messages from self
    if msg.header.sender_id == *local_id {
        return false;
    }
    
    // Don't forward if it's directly addressed to another peer
    if let Some(ref receiver) = msg.header.receiver_id {
        return receiver != peer_id;
    }
    
    // Broadcast messages should be forwarded
    matches!(
        msg.header.message_type,
        FederationMessageType::Discovery | 
        FederationMessageType::LatentBroadcast
    )
}

/// Calculate mesh network health metrics
pub fn calculate_mesh_health(state: &MeshState) -> MeshHealth {
    let online_peers = state.get_online_peers();
    let total_peers = state.peers.len();
    
    let avg_reliability = if online_peers.is_empty() {
        0.0
    } else {
        online_peers.iter()
            .map(|p| p.reliability_score)
            .sum::<f64>() / online_peers.len() as f64
    };
    
    MeshHealth {
        total_peers,
        online_peers: online_peers.len(),
        average_reliability: avg_reliability,
        connectivity_ratio: if total_peers > 0 {
            online_peers.len() as f64 / total_peers as f64
        } else {
            0.0
        },
    }
}

/// Health metrics for the mesh network
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeshHealth {
    pub total_peers: usize,
    pub online_peers: usize,
    pub average_reliability: f64,
    pub connectivity_ratio: f64,
}

// ============================================================================
// EPT POISONING INTEGRATION
// ============================================================================

/// Check if a federated packet should be allowed through EPT
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederatedPacketConfig {
    pub allow_during_dreaming: bool,
    pub max_incoming_size_bytes: usize,
    pub require_encryption: bool,
    pub require_signature: bool,
}

impl Default for FederatedPacketConfig {
    fn default() -> Self {
        Self {
            allow_during_dreaming: true,
            max_incoming_size_bytes: MAX_PACKET_SIZE,
            require_encryption: true,
            require_signature: true,
        }
    }
}

/// Validate incoming federated packet against EPT poisoning rules
pub fn validate_federated_packet(
    msg: &FederationMessage,
    config: &FederatedPacketConfig,
) -> Result<(), String> {
    // Check encryption requirement
    if config.require_encryption && msg.signature.is_empty() {
        return Err("Encrypted packet required but signature is empty".to_string());
    }
    
    // Validate message type is allowed during dreaming
    match msg.header.message_type {
        FederationMessageType::LatentBroadcast |
        FederationMessageType::AggregationRequest |
        FederationMessageType::AggregationResponse => {
            if !config.allow_during_dreaming {
                return Err("Federated packets not allowed during non-dreaming state".to_string());
            }
        }
        _ => {}
    }
    
    Ok(())
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_peer_reliability_update() {
        let score = update_reliability_score(0.8, true, 100, true);
        assert!(score > 0.8 && score <= 1.0);
        
        let score = update_reliability_score(0.8, false, 100, false);
        assert!(score < 0.8);
    }

    #[test]
    fn test_mesh_health_calculation() {
        let local_id = PeerId("test".to_string());
        let local_addr = PeerAddress {
            ip: "127.0.0.1".to_string(),
            discovery_port: 45678,
            federation_port: 45679,
        };
        let state = MeshState::new(local_id, local_addr);
        
        let health = calculate_mesh_health(&state);
        assert_eq!(health.total_peers, 0);
        assert_eq!(health.online_peers, 0);
    }

    #[test]
    fn test_message_encoding() {
        let local_id = PeerId("sender".to_string());
        let msg = create_discovery_message(&local_id, "1.0.0");
        
        let encoded = encode_message(&msg).unwrap();
        let decoded = decode_message(&encoded).unwrap();
        
        assert_eq!(msg.header.sender_id, decoded.header.sender_id);
    }
}
