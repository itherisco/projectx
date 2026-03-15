//! ITHERIS gRPC-Web Client Service
//! 
//! Provides gRPC-Web client connection to the Warden service for streaming
//! metabolic updates and fetching decision proposals in browser environments.
//! 
//! gRPC-Web uses HTTP/1.1 or HTTP/2 with a modified protocol that works
//! through browser proxies.

use crate::state::signals::MetabolicSignals;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// Protobuf generated types for gRPC-Web
pub mod proto {
    include!("../proto/warden.rs");
}

use proto::*;

/// gRPC-Web content type
const GRPC_WEB_CONTENT_TYPE: &str = "application/grpc-web";
const GRPC_WEB_TEXT_CONTENT_TYPE: &str = "application/grpc-web-text";

/// gRPC-Web client wrapper for Warden service
pub struct WardenClientWeb {
    /// Base URL for gRPC-Web endpoint
    base_url: String,
    /// Metabolic state signals
    metabolic_signals: MetabolicSignals,
    /// Auth token for requests
    auth_token: Option<String>,
}

impl WardenClientWeb {
    /// Create a new WardenClientWeb connection
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            metabolic_signals: MetabolicSignals::new(),
            auth_token: None,
        }
    }

    /// Set authentication token
    pub fn with_auth(mut self, token: String) -> Self {
        self.auth_token = Some(token);
        self
    }

    /// Build headers for gRPC-Web request
    fn build_headers(&self) -> Vec<(String, String)> {
        let mut headers = vec![
            ("Content-Type".to_string(), GRPC_WEB_CONTENT_TYPE.to_string()),
            ("X-User-Agent".to_string(), "grpc-web-javascript/0.1".to_string()),
        ];
        
        if let Some(token) = &self.auth_token {
            headers.push(("Authorization".to_string(), format!("Bearer {}", token)));
        }
        
        headers
    }

    /// Subscribe to metabolic telemetry stream via gRPC-Web
    pub async fn subscribe_metabolic(&mut self) -> Result<()> {
        info!("Subscribing to metabolic telemetry stream via gRPC-Web");

        // Create empty request (Empty proto)
        let request_data = prost::encode(&Empty {})?;
        
        let url = format!("{}/WardenService/SubscribeMetabolic", self.base_url);
        
        let client = reqwest::Client::new();
        let mut request = client.post(&url)
            .headers(self.build_headers().into_iter().collect())
            .body(request_data);

        if let Some(token) = &self.auth_token {
            request = request.header("authorization", format!("Bearer {}", token));
        }

        let response = request.send().await
            .context("Failed to send metabolic subscription request")?;

        if !response.status().is_success() {
            anyhow::bail!("gRPC-Web request failed: {}", response.status());
        }

        let body = response.bytes().await
            .context("Failed to read response body")?;

        // Process the stream - in gRPC-Web, streams are delivered as chunked messages
        // Each message has a 5-byte header (1 byte flag + 4 bytes length)
        let mut offset = 0;
        while offset < body.len() {
            if body.len() < offset + 5 {
                break;
            }
            
            let length = u32::from_be_bytes([body[offset + 1], body[offset + 2], body[offset + 3], body[offset + 4]]) as usize;
            
            if body.len() < offset + 5 + length {
                break;
            }
            
            let message_data = &body[offset + 5..offset + 5 + length];
            let snapshot = prost::decode::<MetabolicSnapshot>(message_data)
                .context("Failed to decode metabolic snapshot")?;
            
            self.handle_metabolic_snapshot(snapshot);
            offset += 5 + length;
        }

        warn!("Metabolic stream closed");
        Ok(())
    }

    /// Handle incoming metabolic snapshot
    fn handle_metabolic_snapshot(&self, snapshot: MetabolicSnapshot) {
        let energy = snapshot.energy_level;
        let viability = snapshot.viability_budget;
        let tick_count = snapshot.tick_count;
        let cognitive_mode = snapshot.cognitive_mode;
        let is_dreaming = snapshot.is_dreaming;

        info!(
            energy = energy,
            viability = viability,
            tick_count = tick_count,
            mode = cognitive_mode,
            "Metabolic snapshot received via gRPC-Web"
        );

        self.metabolic_signals.update_from_snapshot(
            energy,
            viability,
            tick_count,
            &cognitive_mode,
            is_dreaming,
        );
    }

    /// Fetch decision proposals via gRPC-Web
    pub async fn get_proposals(&mut self) -> Result<Vec<Proposal>> {
        info!("Fetching decision proposals via gRPC-Web");

        let request_data = prost::encode(&Empty {})?;
        
        let url = format!("{}/WardenService/GetProposals", self.base_url);
        
        let client = reqwest::Client::new();
        let mut request = client.post(&url)
            .headers(self.build_headers().into_iter().collect())
            .body(request_data);

        if let Some(token) = &self.auth_token {
            request = request.header("authorization", format!("Bearer {}", token));
        }

        let response = request.send().await
            .context("Failed to send proposals request")?;

        if !response.status().is_success() {
            anyhow::bail!("gRPC-Web request failed: {}", response.status());
        }

        let body = response.bytes().await
            .context("Failed to read response body")?;

        // Decode multiple proposals from the stream
        let mut proposals = Vec::new();
        let mut offset = 0;
        
        while offset < body.len() {
            if body.len() < offset + 5 {
                break;
            }
            
            let length = u32::from_be_bytes([body[offset + 1], body[offset + 2], body[offset + 3], body[offset + 4]]) as usize;
            
            if body.len() < offset + 5 + length {
                break;
            }
            
            let message_data = &body[offset + 5..offset + 5 + length];
            if let Ok(proposal) = prost::decode::<Proposal>(message_data) {
                proposals.push(proposal);
            }
            offset += 5 + length;
        }

        info!(count = proposals.len(), "Received proposals via gRPC-Web");
        Ok(proposals)
    }

    /// Request TPM unsealing via gRPC-Web
    pub async fn request_unsealing(
        &mut self,
        pcr_values: Vec<Vec<u8>>,
        auth: String,
    ) -> Result<UnsealingResponse> {
        info!("Requesting TPM unsealing via gRPC-Web");

        let request = UnsealingRequest {
            pcr_values,
            auth,
        };
        
        let request_data = prost::encode(&request)?;
        
        let url = format!("{}/WardenService/RequestUnsealing", self.base_url);
        
        let client = reqwest::Client::new();
        let mut req = client.post(&url)
            .headers(self.build_headers().into_iter().collect())
            .body(request_data);

        if let Some(token) = &self.auth_token {
            req = req.header("authorization", format!("Bearer {}", token));
        }

        let response = req.send().await
            .context("Failed to send unsealing request")?;

        if !response.status().is_success() {
            anyhow::bail!("gRPC-Web request failed: {}", response.status());
        }

        let body = response.bytes().await
            .context("Failed to read response body")?;

        // Skip gRPC-Web framing and decode
        if body.len() < 5 {
            anyhow::bail!("Invalid response length");
        }
        
        let length = u32::from_be_bytes([body[1], body[2], body[3], body[4]]) as usize;
        let message_data = &body[5..5 + length];
        
        let response = prost::decode::<UnsealingResponse>(message_data)
            .context("Failed to decode unsealing response")?;

        if response.success {
            info!("TPM unsealing successful via gRPC-Web");
        } else {
            error!("TPM unsealing failed: {}", response.error);
        }

        Ok(response)
    }

    /// Get the metabolic signals
    pub fn metabolic_signals(&self) -> &MetabolicSignals {
        &self.metabolic_signals
    }

    /// Update metabolic signals
    pub fn update_signals(&mut self, signals: MetabolicSignals) {
        self.metabolic_signals = signals;
    }
}

/// Connection configuration for Warden gRPC-Web client
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WardenConfig {
    /// gRPC-Web endpoint URL (e.g., "http://localhost:8080")
    pub endpoint: String,
    /// Use binary or text encoding
    pub use_text_encoding: bool,
    /// Connection timeout in seconds
    pub timeout_secs: u64,
}

impl Default for WardenConfig {
    fn default() -> Self {
        Self {
            endpoint: "http://localhost:8080".to_string(),
            use_text_encoding: false,
            timeout_secs: 30,
        }
    }
}

/// Create a background task for metabolic streaming via gRPC-Web
pub async fn start_metabolic_stream_web(
    endpoint: String,
    metabolic_signals: MetabolicSignals,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    info!(endpoint = endpoint, "Starting metabolic stream via gRPC-Web");

    loop {
        let mut client = WardenClientWeb::new(&endpoint);

        if let Err(e) = client.subscribe_metabolic().await {
            error!(error = %e, "gRPC-Web metabolic stream error, reconnecting in 5s");
            tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_warden_config_default() {
        let config = WardenConfig::default();
        assert_eq!(config.endpoint, "http://localhost:8080");
        assert_eq!(config.timeout_secs, 30);
        assert!(!config.use_text_encoding);
    }

    #[test]
    fn test_grpc_web_content_types() {
        assert_eq!(GRPC_WEB_CONTENT_TYPE, "application/grpc-web");
        assert_eq!(GRPC_WEB_TEXT_CONTENT_TYPE, "application/grpc-web-text");
    }
}
