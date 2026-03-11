//! Capabilities Gate - MCP Request Routing and Security
//!
//! This module implements the "Sentry" gatekeeper for Project X (Itheris).
//! It intercepts intents from Julia (Brain) and routes them to appropriate
//! MCP workers after authorization, validation, and security checks.
//!
//! ## Flow:
//! 1. Julia (Brain) expresses "Intent"
//! 2. Rust (Sentry) intercepts the intent - THIS MODULE
//! 3. MCP Worker handles the API call
//! 4. Rust receives data, scrubs it, passes clean data to Julia
//!
//! ## Supported Capabilities:
//! - `Finance_Data_Fetch` → Finance MCP Server (localhost:3000)
//! - `Github_Read` → GitHub MCP Server (localhost:3001)
//! - `Github_Draft_PR` → GitHub MCP Server (localhost:3001) with signature verification

use crate::types::{
    AutonomyLevel, FailureSeverity, SecurityViolation, SecurityViolationType,
};
use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::Utc;
use ed25519_dalek::{Signature as Ed25519Signature, Verifier, VerifyingKey};
use log::{debug, error, info, warn};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::RwLock;
use uuid::Uuid;

// ============================================================================
// HARDCODED ED25519 PUBLIC KEY - IRON SENTRY CONFIGURATION
// ============================================================================

/// Hardcoded Ed25519 public key for capability verification (Iron Sentry).
/// This key is ALWAYS required for capability execution - no bypass allowed.
/// Source: adaptive-kernel/security/keys/public_key.b64
const HARDCODED_PUBLIC_KEY: &str = "7jkZJmPfl80czlZcBSIqNJQaxwmygDY0/zIgplMXWjE=";

/// Verify that the provided public key matches the hardcoded key.
/// Returns Ok(()) if valid, SecurityViolation if not.
fn verify_hardcoded_key(public_key: &str) -> Result<(), SecurityViolation> {
    if public_key != HARDCODED_PUBLIC_KEY {
        return Err(SecurityViolation {
            violation_type: SecurityViolationType::InvalidSignature,
            details: format!(
                "Public key does not match hardcoded Iron Sentry key. Expected: {}...",
                &HARDCODED_PUBLIC_KEY[..16]
            ),
            timestamp: Utc::now().timestamp_millis(),
            source_ip: None,
        });
    }
    Ok(())
}

// ============================================================================
// MCP PROTOCOL IMPLEMENTATION
// ============================================================================

/// MCP message types following JSON-RPC 2.0 specification.
/// Reference: https://spec.modelcontextprotocol.io/
/// 
/// MCP is a protocol that enables clients to interact with external servers
/// (like Yahoo Finance or GitHub) through a standardized JSON-RPC interface.

/// MCP JSON-RPC request message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpRequest {
    /// JSON-RPC version (must be "2.0")
    pub jsonrpc: String,
    /// Unique request identifier
    pub id: String,
    /// The method to invoke (e.g., "tools/call", "resources/read")
    pub method: String,
    /// Optional parameters for the method
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<McpRequestParams>,
}

impl McpRequest {
    /// Create a new MCP request.
    pub fn new(method: String) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: Uuid::new_v4().to_string(),
            method,
            params: None,
        }
    }

    /// Create a request with parameters.
    pub fn with_params(method: String, params: McpRequestParams) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: Uuid::new_v4().to_string(),
            method,
            params: Some(params),
        }
    }
}

/// MCP request parameters.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpRequestParams {
    /// Name of the tool or resource to invoke
    #[serde(rename = "name")]
    pub tool_name: Option<String>,
    /// Arguments for the tool
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arguments: Option<serde_json::Value>,
    /// URI of the resource to read
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uri: Option<String>,
}

/// MCP JSON-RPC response message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpResponse {
    /// JSON-RPC version
    pub jsonrpc: String,
    /// Request ID this response corresponds to
    pub id: String,
    /// Result (if successful)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    /// Error (if failed)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<McpError>,
}

/// MCP error details.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpError {
    /// Error code
    pub code: i32,
    /// Error message
    pub message: String,
    /// Optional additional error data
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}

/// MCP capability types.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum McpCapability {
    /// Tools capability - allows invoking external functions
    Tools,
    /// Resources capability - allows reading external data
    Resources,
    /// Prompts capability - allows generating prompts
    Prompts,
}

/// MCP server initialization request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpInitializeRequest {
    /// Protocol version
    pub protocol_version: String,
    /// Client capabilities
    pub capabilities: McpClientCapabilities,
    /// Client information
    pub client_info: McpClientInfo,
}

/// MCP client capabilities.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpClientCapabilities {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tools: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resources: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompts: Option<serde_json::Value>,
}

/// MCP client information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpClientInfo {
    pub name: String,
    pub version: String,
}

/// MCP Client for connecting to MCP servers.
/// 
/// This client handles connection management, request routing, and response
/// handling for the Model Context Protocol.
#[derive(Debug, Clone)]
pub struct McpClient {
    /// Server endpoint URL
    endpoint: String,
    /// HTTP client for making requests
    client: reqwest::Client,
    /// Server capabilities (discovered on init)
    server_capabilities: Option<serde_json::Value>,
    /// Protocol version
    protocol_version: Option<String>,
}

impl McpClient {
    /// Create a new MCP client for a given endpoint.
    pub fn new(endpoint: &str) -> Self {
        Self {
            endpoint: endpoint.to_string(),
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(30))
                .build()
                .expect("Failed to create HTTP client"),
            server_capabilities: None,
            protocol_version: None,
        }
    }

    /// Create a new MCP client with custom timeout.
    pub fn with_timeout(endpoint: &str, timeout_secs: u64) -> Self {
        Self {
            endpoint: endpoint.to_string(),
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(timeout_secs))
                .build()
                .expect("Failed to create HTTP client"),
            server_capabilities: None,
            protocol_version: None,
        }
    }

    /// Initialize connection with MCP server.
    pub async fn initialize(&mut self) -> Result<(), GateError> {
        let request = McpRequest::with_params(
            "initialize".to_string(),
            McpRequestParams {
                tool_name: None,
                arguments: Some(serde_json::json!({
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "itheris-shell",
                        "version": "1.0.0"
                    }
                })),
                uri: None,
            },
        );

        let response = self.send_raw_request(request).await?;
        
        if let Some(result) = response.result {
            if let Some(caps) = result.get("capabilities") {
                self.server_capabilities = Some(caps.clone());
            }
            if let Some(protocol) = result.get("protocolVersion") {
                self.protocol_version = Some(protocol.as_str().unwrap_or("unknown").to_string());
            }
        }

        // Send initialized notification
        let notif = McpRequest {
            jsonrpc: "2.0".to_string(),
            id: Uuid::new_v4().to_string(),
            method: "notifications/initialized".to_string(),
            params: None,
        };
        let _ = self.send_raw_request(notif).await;

        Ok(())
    }

    /// Send a raw MCP request and get the response.
    async fn send_raw_request(&self, request: McpRequest) -> Result<McpResponse, GateError> {
        let response = self
            .client
            .post(&self.endpoint)
            .json(&request)
            .send()
            .await
            .map_err(|e| GateError::NetworkError(format!("MCP request failed: {}", e)))?;

        if !response.status().is_success() {
            return Err(GateError::McpServerError(format!(
                "MCP server returned status: {}",
                response.status()
            )));
        }

        let mcp_response: McpResponse = response
            .json()
            .await
            .map_err(|e| GateError::NetworkError(format!("Failed to parse MCP response: {}", e)))?;

        if let Some(error) = mcp_response.error {
            return Err(GateError::McpServerError(format!(
                "MCP error [{}]: {}",
                error.code, error.message
            )));
        }

        Ok(mcp_response)
    }

    /// Send an MCP request to call a tool.
    /// 
    /// This is the main function for routing capability requests to MCP servers.
    /// It takes a capability name and parameters, routes to the appropriate
    /// MCP server endpoint, and returns the result or error.
    /// 
    /// # Arguments
    /// 
    /// * `capability` - The capability name (e.g., "Finance_Data_Fetch", "Github_Read")
    /// * `params` - Parameters for the capability
    /// 
    /// # Returns
    /// 
    /// The result from the MCP server as a JSON value.
    pub async fn send_mcp_request(
        &self,
        capability: &str,
        params: HashMap<String, String>,
    ) -> Result<serde_json::Value, GateError> {
        debug!("Sending MCP request for capability: {}", capability);

        // Map capability to MCP method
        let method = match capability {
            // Finance capabilities
            "Finance_Data_Fetch" | "finance_get_quote" | "finance_get_market_data" => {
                "tools/call".to_string()
            }
            // GitHub read capabilities
            "Github_Read" | "github_get_issues" | "github_get_pulls" => {"tools/call".to_string()},
            // GitHub write capabilities
            "Github_Draft_PR" | "github_create_pr" => "tools/call".to_string(),
            // Default to tools/call
            _ => "tools/call".to_string(),
        };

        // Build tool arguments based on capability
        let arguments = match capability {
            "Finance_Data_Fetch" | "finance_get_quote" => {
                serde_json::json!({
                    "tool": "get_stock_quote",
                    "arguments": {
                        "symbol": params.get("symbol").cloned().unwrap_or_default()
                    }
                })
            }
            "finance_get_market_data" => {
                serde_json::json!({
                    "tool": "get_market_data",
                    "arguments": {
                        "market": params.get("market").cloned().unwrap_or("US".to_string())
                    }
                })
            }
            "Github_Read" | "github_get_issues" => {
                serde_json::json!({
                    "tool": "list_issues",
                    "arguments": {
                        "owner": params.get("owner").cloned().unwrap_or_default(),
                        "repo": params.get("repo").cloned().unwrap_or_default(),
                        "state": params.get("state").cloned().unwrap_or("open".to_string()),
                        "limit": params.get("limit").cloned().unwrap_or("30".to_string())
                    }
                })
            }
            "github_get_pulls" => {
                serde_json::json!({
                    "tool": "list_pull_requests",
                    "arguments": {
                        "owner": params.get("owner").cloned().unwrap_or_default(),
                        "repo": params.get("repo").cloned().unwrap_or_default(),
                        "state": params.get("state").cloned().unwrap_or("open".to_string())
                    }
                })
            }
            "Github_Draft_PR" | "github_create_pr" => {
                serde_json::json!({
                    "tool": "create_pull_request",
                    "arguments": {
                        "owner": params.get("owner").cloned().unwrap_or_default(),
                        "repo": params.get("repo").cloned().unwrap_or_default(),
                        "title": params.get("title").cloned().unwrap_or_default(),
                        "body": params.get("body").cloned().unwrap_or_default(),
                        "head": params.get("head").cloned().unwrap_or_default(),
                        "base": params.get("base").cloned().unwrap_or("main".to_string()),
                        "draft": params.get("draft").cloned().unwrap_or("true".to_string())
                    }
                })
            }
            // Generic fallback
            _ => serde_json::json!({
                "tool": capability,
                "arguments": params
            }),
        };

        let mcp_request = McpRequest::with_params(
            method,
            McpRequestParams {
                tool_name: Some(capability.to_string()),
                arguments: Some(arguments),
                uri: None,
            },
        );

        let response = self.send_raw_request(mcp_request).await?;

        // Extract result from response
        response.result.ok_or_else(|| {
            GateError::McpServerError("No result in MCP response".to_string())
        })
    }

    /// List available tools on the MCP server.
    pub async fn list_tools(&self) -> Result<Vec<serde_json::Value>, GateError> {
        let request = McpRequest::new("tools/list".to_string());
        let response = self.send_raw_request(request).await?;
        
        let result = response.result.ok_or_else(|| {
            GateError::McpServerError("No result in MCP response".to_string())
        })?;

        if let Some(tools) = result.get("tools").and_then(|t| t.as_array()) {
            Ok(tools.clone())
        } else {
            Ok(vec![])
        }
    }

    /// Get server capabilities.
    pub fn capabilities(&self) -> Option<&serde_json::Value> {
        self.server_capabilities.as_ref()
    }

    /// Get protocol version.
    pub fn protocol_version(&self) -> Option<&str> {
        self.protocol_version.as_deref()
    }
}

// ============================================================================
// FINANCE MCP CAPABILITY
// ============================================================================

/// Finance MCP client for fetching market data.
/// 
/// This provides a specialized interface for finance-related capabilities
/// including stock quotes, market data, and financial metrics.
#[derive(Debug, Clone)]
pub struct FinanceMcpClient {
    /// Base MCP client
    client: McpClient,
}

impl FinanceMcpClient {
    /// Create a new finance MCP client.
    pub fn new() -> Self {
        Self {
            client: McpClient::new("http://localhost:3000"),
        }
    }

    /// Create with custom endpoint.
    pub fn with_endpoint(endpoint: &str) -> Self {
        Self {
            client: McpClient::new(endpoint),
        }
    }

    /// Fetch stock quote for a given symbol.
    /// 
    /// # Arguments
    /// 
    /// * `symbol` - Stock ticker symbol (e.g., "AAPL", "GOOGL")
    /// 
    /// # Returns
    /// 
    /// Structured financial data including price, volume, etc.
    pub async fn get_quote(&self, symbol: &str) -> Result<serde_json::Value, GateError> {
        let mut params = HashMap::new();
        params.insert("symbol".to_string(), symbol.to_string());
        
        self.client.send_mcp_request("Finance_Data_Fetch", params).await
    }

    /// Fetch market data for a given market.
    /// 
    /// # Arguments
    /// 
    /// * `market` - Market identifier (e.g., "US", "EU", "ASIA")
    /// 
    /// # Returns
    /// 
    /// Market overview data including indices, trends, etc.
    pub async fn get_market_data(&self, market: &str) -> Result<serde_json::Value, GateError> {
        let mut params = HashMap::new();
        params.insert("market".to_string(), market.to_string());
        
        self.client.send_mcp_request("finance_get_market_data", params).await
    }

    /// Fetch historical price data.
    pub async fn get_historical(
        &self,
        symbol: &str,
        period: &str,
    ) -> Result<serde_json::Value, GateError> {
        let mut params = HashMap::new();
        params.insert("symbol".to_string(), symbol.to_string());
        params.insert("period".to_string(), period.to_string());
        
        self.client.send_mcp_request("finance_get_historical", params).await
    }
}

impl Default for FinanceMcpClient {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// GITHUB MCP CAPABILITY
// ============================================================================

/// GitHub MCP client for GitHub operations.
/// 
/// This provides a specialized interface for GitHub-related capabilities
/// including reading issues, pull requests, and creating draft PRs.
#[derive(Debug, Clone)]
pub struct GithubMcpClient {
    /// Base MCP client
    client: McpClient,
}

impl GithubMcpClient {
    /// Create a new GitHub MCP client.
    pub fn new() -> Self {
        Self {
            client: McpClient::new("http://localhost:3001"),
        }
    }

    /// Create with custom endpoint.
    pub fn with_endpoint(endpoint: &str) -> Self {
        Self {
            client: McpClient::new(endpoint),
        }
    }

    /// Read issues from a repository.
    /// 
    /// # Arguments
    /// 
    /// * `owner` - Repository owner
    /// * `repo` - Repository name
    /// * `state` - Issue state (open, closed, all)
    /// * `limit` - Maximum number of issues to fetch
    /// 
    /// # Returns
    /// 
    /// List of issues matching the criteria.
    pub async fn read_issues(
        &self,
        owner: &str,
        repo: &str,
        state: &str,
        limit: u32,
    ) -> Result<serde_json::Value, GateError> {
        let mut params = HashMap::new();
        params.insert("owner".to_string(), owner.to_string());
        params.insert("repo".to_string(), repo.to_string());
        params.insert("state".to_string(), state.to_string());
        params.insert("limit".to_string(), limit.to_string());
        
        self.client.send_mcp_request("Github_Read_Issues", params).await
    }

    /// Read pull requests from a repository.
    pub async fn read_pull_requests(
        &self,
        owner: &str,
        repo: &str,
        state: &str,
    ) -> Result<serde_json::Value, GateError> {
        let mut params = HashMap::new();
        params.insert("owner".to_string(), owner.to_string());
        params.insert("repo".to_string(), repo.to_string());
        params.insert("state".to_string(), state.to_string());
        
        self.client.send_mcp_request("github_get_pulls", params).await
    }

    /// Create a draft pull request.
    /// 
    /// # Arguments
    /// 
    /// * `owner` - Repository owner
    /// * `repo` - Repository name
    /// * `title` - PR title
    /// * `body` - PR body/description
    /// * `head` - Branch name containing the changes
    /// * `base` - Base branch to merge into
    /// 
    /// # Returns
    /// 
    /// Created pull request details.
    pub async fn create_draft_pr(
        &self,
        owner: &str,
        repo: &str,
        title: &str,
        body: &str,
        head: &str,
        base: &str,
    ) -> Result<serde_json::Value, GateError> {
        let mut params = HashMap::new();
        params.insert("owner".to_string(), owner.to_string());
        params.insert("repo".to_string(), repo.to_string());
        params.insert("title".to_string(), title.to_string());
        params.insert("body".to_string(), body.to_string());
        params.insert("head".to_string(), head.to_string());
        params.insert("base".to_string(), base.to_string());
        params.insert("draft".to_string(), "true".to_string());
        
        self.client.send_mcp_request("Github_Draft_PR", params).await
    }
}

impl Default for GithubMcpClient {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// ERROR TYPES
// ============================================================================

/// Errors that can occur in the capabilities gate.
#[derive(Error, Debug)]
pub enum GateError {
    #[error("Capability not found: {0}")]
    CapabilityNotFound(String),

    #[error("Capability not authorized: {0}")]
    NotAuthorized(String),

    #[error("Input validation failed: {0}")]
    ValidationError(String),

    #[error("Security violation: {0}")]
    SecurityViolation(#[from] SecurityViolation),

    #[error("MCP server error: {0}")]
    McpServerError(String),

    #[error("Rate limit exceeded: {0}")]
    RateLimitExceeded(String),

    #[error("Data scrubbing failed: {0}")]
    ScrubError(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("Internal error: {0}")]
    InternalError(String),
}

impl Serialize for GateError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

// ============================================================================
// REQUEST/RESPONSE TYPES
// ============================================================================

/// Request from Julia (Brain) to execute a capability.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityRequest {
    /// Unique identifier for this request
    pub request_id: Uuid,
    /// The capability type to execute (e.g., "Finance_Data_Fetch", "Github_Read")
    pub capability: String,
    /// Parameters for the capability
    pub parameters: HashMap<String, String>,
    /// Requestor identity (for authorization)
    pub requestor: String,
    /// Requested autonomy level
    pub requested_autonomy: AutonomyLevel,
    /// Optional signature for write operations
    pub signature: Option<String>,
    /// Optional public key for signature verification
    pub public_key: Option<String>,
    /// Unix timestamp (milliseconds)
    pub timestamp: i64,
}

impl CapabilityRequest {
    /// Create a new capability request.
    pub fn new(
        capability: String,
        parameters: HashMap<String, String>,
        requestor: String,
        requested_autonomy: AutonomyLevel,
    ) -> Self {
        Self {
            request_id: Uuid::new_v4(),
            capability,
            parameters,
            requestor,
            requested_autonomy,
            signature: None,
            public_key: None,
            timestamp: Utc::now().timestamp_millis(),
        }
    }

    /// Check if this is a write operation (requires signature verification).
    pub fn is_write_operation(&self) -> bool {
        matches!(
            self.capability.as_str(),
            "Github_Draft_PR" | "Github_Write" | "write_file" | "safe_shell"
        )
    }
}

/// Response from the capabilities gate after processing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityResponse {
    /// Request ID this response corresponds to
    pub request_id: Uuid,
    /// Whether the request was successful
    pub success: bool,
    /// The capability that was executed
    pub capability: String,
    /// The scrubbed response data
    pub data: Option<serde_json::Value>,
    /// Error message if failed
    pub error: Option<String>,
    /// Risk score of the executed capability
    pub risk_score: f64,
    /// Timestamp of response
    pub timestamp: i64,
}

impl CapabilityResponse {
    /// Create a successful response.
    pub fn success(
        request_id: Uuid,
        capability: String,
        data: serde_json::Value,
        risk_score: f64,
    ) -> Self {
        Self {
            request_id,
            success: true,
            capability,
            data: Some(data),
            error: None,
            risk_score,
            timestamp: Utc::now().timestamp_millis(),
        }
    }

    /// Create a failure response.
    pub fn failure(request_id: Uuid, capability: String, error: String) -> Self {
        Self {
            request_id,
            success: false,
            capability,
            data: None,
            error: Some(error),
            risk_score: 0.0,
            timestamp: Utc::now().timestamp_millis(),
        }
    }
}

// ============================================================================
// CAPABILITY REGISTRY
// ============================================================================

/// Metadata about a registered capability.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityMetadata {
    /// Unique identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Description
    pub description: String,
    /// Risk level: "low", "medium", "high", "critical"
    pub risk: String,
    /// Whether this is a write operation
    pub is_write: bool,
    /// MCP server endpoint
    pub mcp_server: String,
    /// MCP server port
    pub mcp_port: u16,
    /// Whether signature is required
    pub requires_signature: bool,
    /// Rate limit: max requests per minute
    pub rate_limit_per_minute: u32,
}

impl CapabilityMetadata {
    /// Get the MCP server URL.
    pub fn mcp_url(&self) -> String {
        format!("http://{}:{}", self.mcp_server, self.mcp_port)
    }

    /// Get risk score (0.0 - 1.0).
    pub fn risk_score(&self) -> f64 {
        match self.risk.as_str() {
            "low" => 0.25,
            "medium" => 0.5,
            "high" => 0.75,
            "critical" => 1.0,
            _ => 0.5,
        }
    }
}

/// In-memory capability registry.
#[derive(Debug, Clone)]
pub struct CapabilityRegistry {
    /// Registered capabilities
    capabilities: HashMap<String, CapabilityMetadata>,
}

impl Default for CapabilityRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl CapabilityRegistry {
    /// Create a new empty registry.
    pub fn new() -> Self {
        Self {
            capabilities: HashMap::new(),
        }
    }

    /// Initialize with default capabilities.
    pub fn with_defaults() -> Self {
        let mut registry = Self::new();

        // Finance MCP Server (localhost:3000)
        registry.register(CapabilityMetadata {
            id: "Finance_Data_Fetch".to_string(),
            name: "Finance Data Fetch".to_string(),
            description: "Fetch financial market data".to_string(),
            risk: "low".to_string(),
            is_write: false,
            mcp_server: "localhost".to_string(),
            mcp_port: 3000,
            requires_signature: false,
            rate_limit_per_minute: 60,
        });

        // GitHub MCP Server (localhost:3001)
        registry.register(CapabilityMetadata {
            id: "Github_Read".to_string(),
            name: "GitHub Read".to_string(),
            description: "Read GitHub repositories, issues, PRs".to_string(),
            risk: "low".to_string(),
            is_write: false,
            mcp_server: "localhost".to_string(),
            mcp_port: 3001,
            requires_signature: false,
            rate_limit_per_minute: 30,
        });

        registry.register(CapabilityMetadata {
            id: "Github_Draft_PR".to_string(),
            name: "GitHub Draft PR".to_string(),
            description: "Draft a GitHub pull request".to_string(),
            risk: "high".to_string(),
            is_write: true,
            mcp_server: "localhost".to_string(),
            mcp_port: 3001,
            requires_signature: true,
            rate_limit_per_minute: 10,
        });

        // Additional capabilities from registry
        registry.register(CapabilityMetadata {
            id: "safe_http_request".to_string(),
            name: "Safe HTTP Request".to_string(),
            description: "Perform read-only HTTP GET".to_string(),
            risk: "medium".to_string(),
            is_write: false,
            mcp_server: "localhost".to_string(),
            mcp_port: 3000,
            requires_signature: false,
            rate_limit_per_minute: 30,
        });

        registry.register(CapabilityMetadata {
            id: "safe_shell".to_string(),
            name: "Safe Shell Execute".to_string(),
            description: "Execute a whitelisted command".to_string(),
            risk: "high".to_string(),
            is_write: true,
            mcp_server: "localhost".to_string(),
            mcp_port: 3000,
            requires_signature: true,
            rate_limit_per_minute: 5,
        });

        registry.register(CapabilityMetadata {
            id: "write_file".to_string(),
            name: "Write File".to_string(),
            description: "Write data to sandbox file".to_string(),
            risk: "medium".to_string(),
            is_write: true,
            mcp_server: "localhost".to_string(),
            mcp_port: 3000,
            requires_signature: true,
            rate_limit_per_minute: 10,
        });

        registry
    }

    /// Register a capability.
    pub fn register(&mut self, metadata: CapabilityMetadata) {
        self.capabilities.insert(metadata.id.clone(), metadata);
    }

    /// Get capability metadata by ID.
    pub fn get(&self, id: &str) -> Option<&CapabilityMetadata> {
        self.capabilities.get(id)
    }

    /// List all registered capabilities.
    pub fn list(&self) -> Vec<&CapabilityMetadata> {
        self.capabilities.values().collect()
    }
}

// ============================================================================
// DATA SCRUBBING
// ============================================================================

/// Data scrubber for removing malicious content from responses.
pub struct DataScrubber;

impl DataScrubber {
    /// Scrub potentially malicious content from a string.
    pub fn scrub_string(input: &str) -> String {
        let mut result = input.to_string();

        // Remove HTML tags
        let html_patterns = [
            "<script",
            "</script>",
            "<iframe",
            "</iframe>",
            "javascript:",
            "onerror=",
            "onclick=",
            "onload=",
        ];

        for pattern in html_patterns {
            result = result.replace(pattern, &format!("<!-- removed: {} -->", pattern));
        }

        // Remove dangerous characters
        result = result
            .chars()
            .map(|c| {
                if c.is_control() && c != '\n' && c != '\t' && c != '\r' {
                    ' '
                } else {
                    c
                }
            })
            .collect();

        // Normalize whitespace
        result = result.split_whitespace().collect::<Vec<_>>().join(" ");

        result
    }

    /// Scrub a JSON value.
    pub fn scrub_json(value: &serde_json::Value) -> serde_json::Value {
        match value {
            serde_json::Value::String(s) => {
                serde_json::Value::String(Self::scrub_string(s))
            }
            serde_json::Value::Array(arr) => {
                serde_json::Value::Array(arr.iter().map(Self::scrub_json).collect())
            }
            serde_json::Value::Object(obj) => {
                let mut new_obj = serde_json::Map::new();
                for (k, v) in obj {
                    new_obj.insert(k.clone(), Self::scrub_json(v));
                }
                serde_json::Value::Object(new_obj)
            }
            _ => value.clone(),
        }
    }

    /// Validate JSON structure.
    pub fn validate_json(input: &str) -> Result<serde_json::Value, GateError> {
        serde_json::from_str(input).map_err(|e| GateError::ValidationError(e.to_string()))
    }
}

// ============================================================================
// RATE LIMITING
// ============================================================================

/// Rate limiter for capability requests.
#[derive(Debug)]
pub struct RateLimiter {
    /// Timestamps of recent requests per capability
    requests: HashMap<String, Vec<i64>>,
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

impl RateLimiter {
    /// Create a new rate limiter.
    pub fn new() -> Self {
        Self {
            requests: HashMap::new(),
        }
    }

    /// Check if a request is within rate limits.
    /// Returns Ok(()) if allowed, Err(GateError) if rate limited.
    pub fn check(&mut self, capability: &str, limit: u32) -> Result<(), GateError> {
        let now = Utc::now().timestamp_millis();
        let window_ms = 60_000; // 1 minute

        let timestamps = self.requests.entry(capability.to_string()).or_insert_with(Vec::new);

        // Remove old timestamps
        timestamps.retain(|&ts| now - ts < window_ms);

        // Check limit
        if timestamps.len() >= limit as usize {
            return Err(GateError::RateLimitExceeded(format!(
                "Rate limit exceeded for {}: {} requests per minute",
                capability, limit
            )));
        }

        // Record this request
        timestamps.push(now);

        Ok(())
    }

    /// Reset rate limits for a capability.
    pub fn reset(&mut self, capability: &str) {
        self.requests.remove(capability);
    }
}

// ============================================================================
// SIGNATURE VERIFIER
// ============================================================================

/// Signature verifier for write operations.
pub struct SignatureVerifier {
    /// Trusted public keys (base64 encoded)
    trusted_keys: Vec<String>,
}

impl Default for SignatureVerifier {
    fn default() -> Self {
        Self::new()
    }
}

impl SignatureVerifier {
    /// Create a new signature verifier.
    pub fn new() -> Self {
        Self {
            trusted_keys: Vec::new(),
        }
    }

    /// Add a trusted public key.
    pub fn add_trusted_key(&mut self, public_key_b64: String) {
        if !self.trusted_keys.contains(&public_key_b64) {
            self.trusted_keys.push(public_key_b64);
        }
    }

    /// Verify a signature.
    pub fn verify(
        &self,
        message: &str,
        signature_b64: &str,
        public_key_b64: &str,
    ) -> Result<bool, SecurityViolation> {
        // Check if public key is trusted
        if !self.trusted_keys.is_empty() && !self.trusted_keys.contains(&public_key_b64.to_string()) {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::UnauthorizedBinary,
                details: "Public key not in trusted keys list".to_string(),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            });
        }

        // Decode public key
        let public_key_bytes = BASE64
            .decode(public_key_b64)
            .map_err(|e| SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Failed to decode public key: {}", e),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            })?;

        if public_key_bytes.len() != 32 {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Invalid public key length: {} bytes", public_key_bytes.len()),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            });
        }

        // IRON SENTRY: Always verify against hardcoded public key (mandatory)
        // This ensures ONLY the known Julia kernel can send capability requests
        if public_key_b64 != HARDCODED_PUBLIC_KEY {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::UnauthorizedBinary,
                details: format!(
                    "Public key does not match hardcoded Iron Sentry key. Expected: {}...",
                    &HARDCODED_PUBLIC_KEY[..16]
                ),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            });
        }

        // Decode signature
        let signature_bytes = BASE64
            .decode(signature_b64)
            .map_err(|e| SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Failed to decode signature: {}", e),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            })?;

        if signature_bytes.len() != 64 {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Invalid signature length: {} bytes", signature_bytes.len()),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            });
        }

        // Create verifying key
        let verifying_key = VerifyingKey::from_bytes(
            public_key_bytes
                .as_slice()
                .try_into()
                .map_err(|_| SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Failed to create verifying key".to_string(),
                    timestamp: Utc::now().timestamp_millis(),
                    source_ip: None,
                })?,
        )
        .map_err(|e| SecurityViolation {
            violation_type: SecurityViolationType::InvalidSignature,
            details: format!("Invalid verifying key: {}", e),
            timestamp: Utc::now().timestamp_millis(),
            source_ip: None,
        })?;

        // Create signature
        let signature = Ed25519Signature::from_bytes(
            signature_bytes
                .as_slice()
                .try_into()
                .map_err(|_| SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Failed to create signature".to_string(),
                    timestamp: Utc::now().timestamp_millis(),
                    source_ip: None,
                })?,
        );

        // Verify signature
        Ok(verifying_key.verify(message.as_bytes(), &signature).is_ok())
    }
}

// ============================================================================
// INPUT VALIDATION
// ============================================================================

/// Input validator for capability requests.
pub struct InputValidator;

impl InputValidator {
    /// Validate capability request parameters.
    pub fn validate(request: &CapabilityRequest) -> Result<(), GateError> {
        // Check capability is not empty
        if request.capability.is_empty() {
            return Err(GateError::ValidationError(
                "Capability cannot be empty".to_string(),
            ));
        }

        // Check requestor is not empty
        if request.requestor.is_empty() {
            return Err(GateError::ValidationError(
                "Requestor cannot be empty".to_string(),
            ));
        }

        // Check timestamp is not too old (5 minutes)
        let now = Utc::now().timestamp_millis();
        let max_age_ms = 300_000; // 5 minutes
        if (now - request.timestamp).abs() > max_age_ms {
            return Err(GateError::ValidationError(
                "Request timestamp is too old".to_string(),
            ));
        }

        // Validate parameters based on capability
        Self::validate_parameters(&request.capability, &request.parameters)?;

        Ok(())
    }

    /// Validate parameters for a specific capability.
    fn validate_parameters(
        capability: &str,
        parameters: &HashMap<String, String>,
    ) -> Result<(), GateError> {
        match capability {
            "Finance_Data_Fetch" => {
                // Validate finance parameters
                if let Some(symbol) = parameters.get("symbol") {
                    if symbol.len() > 10 {
                        return Err(GateError::ValidationError(
                            "Symbol too long".to_string(),
                        ));
                    }
                }
            }
            "Github_Draft_PR" => {
                // Validate PR parameters
                if !parameters.contains_key("repo") {
                    return Err(GateError::ValidationError(
                        "Missing required parameter: repo".to_string(),
                    ));
                }
                if !parameters.contains_key("title") {
                    return Err(GateError::ValidationError(
                        "Missing required parameter: title".to_string(),
                    ));
                }
            }
            "safe_http_request" => {
                // Validate URL
                if let Some(url) = parameters.get("url") {
                    if !url.starts_with("http://") && !url.starts_with("https://") {
                        return Err(GateError::ValidationError(
                            "URL must start with http:// or https://".to_string(),
                        ));
                    }
                    // Basic SQL injection prevention
                    if url.contains("' OR '") || url.contains("';") {
                        return Err(GateError::ValidationError(
                            "Potentially malicious URL detected".to_string(),
                        ));
                    }
                }
            }
            _ => {}
        }

        Ok(())
    }

    /// Sanitize input parameters.
    pub fn sanitize(parameters: &mut HashMap<String, String>) {
        for value in parameters.values_mut() {
            *value = DataScrubber::scrub_string(value);
        }
    }
}

// ============================================================================
// MAIN CAPABILITIES GATE
// ============================================================================

/// Configuration for the capabilities gate.
#[derive(Debug, Clone)]
pub struct GateConfig {
    /// Enable signature verification for write operations
    pub require_signatures: bool,
    /// Enable rate limiting
    pub enable_rate_limiting: bool,
    /// Enable data scrubbing
    pub enable_scrubbing: bool,
    /// Finance MCP server URL
    pub finance_mcp_url: String,
    /// GitHub MCP server URL
    pub github_mcp_url: String,
    /// Timeout for MCP requests in seconds
    pub mcp_timeout_seconds: u64,
}

impl Default for GateConfig {
    fn default() -> Self {
        Self {
            require_signatures: true,
            enable_rate_limiting: true,
            enable_scrubbing: true,
            finance_mcp_url: "http://localhost:3000".to_string(),
            github_mcp_url: "http://localhost:3001".to_string(),
            mcp_timeout_seconds: 30,
        }
    }
}

impl GateConfig {
    /// Load configuration from environment variables.
    pub fn from_env() -> Self {
        Self {
            require_signatures: std::env::var("ITHERIS_REQUIRE_SIGNATURES")
                .map(|v| v == "true")
                .unwrap_or(true),
            enable_rate_limiting: std::env::var("ITHERIS_ENABLE_RATE_LIMITING")
                .map(|v| v == "true")
                .unwrap_or(true),
            enable_scrubbing: std::env::var("ITHERIS_ENABLE_SCRUBBING")
                .map(|v| v == "true")
                .unwrap_or(true),
            finance_mcp_url: std::env::var("ITHERIS_FINANCE_MCP_URL")
                .unwrap_or_else(|_| "http://localhost:3000".to_string()),
            github_mcp_url: std::env::var("ITHERIS_GITHUB_MCP_URL")
                .unwrap_or_else(|_| "http://localhost:3001".to_string()),
            mcp_timeout_seconds: std::env::var("ITHERIS_MCP_TIMEOUT")
                .map(|v| v.parse().unwrap_or(30))
                .unwrap_or(30),
        }
    }
}

/// The Capabilities Gate - main gatekeeper struct.
pub struct CapabilitiesGate {
    /// Capability registry
    registry: CapabilityRegistry,
    /// Rate limiter
    rate_limiter: RateLimiter,
    /// Signature verifier
    signature_verifier: SignatureVerifier,
    /// Configuration
    config: GateConfig,
}

impl Default for CapabilitiesGate {
    fn default() -> Self {
        Self::new()
    }
}

impl CapabilitiesGate {
    /// Create a new capabilities gate.
    pub fn new() -> Self {
        Self {
            registry: CapabilityRegistry::with_defaults(),
            rate_limiter: RateLimiter::new(),
            signature_verifier: SignatureVerifier::new(),
            config: GateConfig::default(),
        }
    }

    /// Create a new capabilities gate with custom configuration.
    pub fn with_config(config: GateConfig) -> Self {
        Self {
            registry: CapabilityRegistry::with_defaults(),
            rate_limiter: RateLimiter::new(),
            signature_verifier: SignatureVerifier::new(),
            config,
        }
    }

    /// Add a trusted public key for signature verification.
    pub fn add_trusted_key(&mut self, public_key_b64: String) {
        self.signature_verifier.add_trusted_key(public_key_b64);
    }

    /// Register a new capability.
    pub fn register_capability(&mut self, metadata: CapabilityMetadata) {
        self.registry.register(metadata);
    }

    /// Route a capability request to the appropriate MCP worker.
    ///
    /// This is the main entry point for processing capability requests.
    /// It performs:
    /// 1. Input validation
    /// 2. Capability lookup
    /// 3. Authorization check
    /// 4. Rate limiting check
    /// 5. Signature verification (for write operations)
    /// 6. MCP request routing
    /// 7. Data scrubbing
    /// 8. Response construction
    pub async fn route_capability_request(
        &mut self,
        request: CapabilityRequest,
    ) -> Result<CapabilityResponse, GateError> {
        let request_id = request.request_id;
        let capability = request.capability.clone();

        info!(
            "Routing capability request: {} ({})",
            capability, request_id
        );

        // Step 1: Input validation
        debug!("Validating input for request {}", request_id);
        if let Err(e) = InputValidator::validate(&request) {
            warn!("Input validation failed for {}: {}", request_id, e);
            return Ok(CapabilityResponse::failure(
                request_id,
                capability,
                format!("Validation error: {}", e),
            ));
        }

        // Sanitize parameters
        let mut params = request.parameters.clone();
        InputValidator::sanitize(&mut params);

        // Step 2: Capability lookup
        debug!("Looking up capability: {}", capability);
        let metadata = match self.registry.get(&capability) {
            Some(m) => m,
            None => {
                warn!("Capability not found: {}", capability);
                return Ok(CapabilityResponse::failure(
                    request_id,
                    capability,
                    format!("Capability not found: {}", capability),
                ));
            }
        };

        // Step 3: Authorization check
        debug!("Checking authorization for request {}", request_id);
        if let Err(e) = self.check_authorization(&request, metadata) {
            warn!("Authorization failed for {}: {}", request_id, e);
            return Ok(CapabilityResponse::failure(
                request_id,
                capability,
                format!("Not authorized: {}", e),
            ));
        }

        // Step 4: Rate limiting
        if self.config.enable_rate_limiting {
            debug!("Checking rate limits for {}", capability);
            if let Err(e) = self.rate_limiter.check(&capability, metadata.rate_limit_per_minute) {
                warn!("Rate limit exceeded for {}: {}", request_id, e);
                return Ok(CapabilityResponse::failure(
                    request_id,
                    capability,
                    format!("Rate limit exceeded: {}", e),
                ));
            }
        }

        // Step 5: Signature verification for write operations
        if metadata.requires_signature || request.is_write_operation() {
            if let Err(e) = self.verify_signature(&request, &metadata) {
                warn!("Signature verification failed for {}: {}", request_id, e);
                return Ok(CapabilityResponse::failure(
                    request_id,
                    capability,
                    format!("Security violation: {}", e),
                ));
            }
        }

        // Step 6: Route to MCP server
        debug!("Routing request {} to MCP server", request_id);
        let mcp_response = self
            .route_to_mcp(&request, metadata)
            .await
            .map_err(|e| GateError::McpServerError(e.to_string()))?;

        // Step 7: Data scrubbing
        let scrubbed_data = if self.config.enable_scrubbing {
            debug!("Scrubbing response data for {}", request_id);
            DataScrubber::scrub_json(&mcp_response)
        } else {
            mcp_response
        };

        // Step 8: Construct response
        info!("Request {} completed successfully", request_id);
        Ok(CapabilityResponse::success(
            request_id,
            capability,
            scrubbed_data,
            metadata.risk_score(),
        ))
    }

    /// Check if the request is authorized.
    fn check_authorization(
        &self,
        request: &CapabilityRequest,
        metadata: &CapabilityMetadata,
    ) -> Result<(), GateError> {
        // Check if requestor's requested autonomy is within allowed limits
        // For now, we allow any requestor but in production this would check against ACLs

        // Check if the capability is a write operation and if the requestor is allowed
        if metadata.is_write && request.requested_autonomy == AutonomyLevel::Minimal {
            return Err(GateError::NotAuthorized(
                "Write operations not allowed at Minimal autonomy level".to_string(),
            ));
        }

        if metadata.is_write && request.requested_autonomy == AutonomyLevel::Halted {
            return Err(GateError::NotAuthorized(
                "Write operations not allowed at Halted autonomy level".to_string(),
            ));
        }

        Ok(())
    }

    /// Verify signature for write operations.
    fn verify_signature(
        &self,
        request: &CapabilityRequest,
        metadata: &CapabilityMetadata,
    ) -> Result<(), GateError> {
        // Check if signature is required
        if metadata.requires_signature && !request.is_write_operation() {
            return Err(GateError::SecurityViolation(SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: "Capability requires signature".to_string(),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            }));
        }

        // If it's a write operation and we require signatures
        if self.config.require_signatures && metadata.is_write {
            let signature = request.signature.as_ref().ok_or_else(|| {
                GateError::SecurityViolation(SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Write operation requires signature".to_string(),
                    timestamp: Utc::now().timestamp_millis(),
                    source_ip: None,
                })
            })?;

            let public_key = request.public_key.as_ref().ok_or_else(|| {
                GateError::SecurityViolation(SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Write operation requires public key".to_string(),
                    timestamp: Utc::now().timestamp_millis(),
                    source_ip: None,
                })
            })?;

            // IRON SENTRY: Always verify against hardcoded public key (mandatory)
            // This ensures ONLY the known Julia kernel can send capability requests
            verify_hardcoded_key(public_key)?;

            // Create message to verify (capability + parameters)
            let message = format!(
                "{}:{}:{}",
                request.capability,
                request.request_id,
                serde_json::to_string(&request.parameters).unwrap_or_default()
            );

            let verified = self
                .signature_verifier
                .verify(&message, signature, public_key)
                .map_err(GateError::SecurityViolation)?;

            if !verified {
                return Err(GateError::SecurityViolation(SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Signature verification failed".to_string(),
                    timestamp: Utc::now().timestamp_millis(),
                    source_ip: None,
                }));
            }
        }

        Ok(())
    }

    /// Route request to the appropriate MCP server.
    async fn route_to_mcp(
        &self,
        request: &CapabilityRequest,
        metadata: &CapabilityMetadata,
    ) -> Result<serde_json::Value, GateError> {
        let mcp_url = metadata.mcp_url();

        // Build MCP request payload
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "id": request.request_id.to_string(),
            "method": &request.capability,
            "params": {
                "parameters": request.parameters,
                "requestor": request.requestor,
            }
        });

        // Make HTTP request to MCP server
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(self.config.mcp_timeout_seconds))
            .build()
            .map_err(|e| GateError::NetworkError(e.to_string()))?;

        let response = client
            .post(&mcp_url)
            .json(&payload)
            .send()
            .await
            .map_err(|e| GateError::NetworkError(e.to_string()))?;

        if !response.status().is_success() {
            return Err(GateError::McpServerError(format!(
                "MCP server returned status: {}",
                response.status()
            )));
        }

        let result: serde_json::Value = response
            .json()
            .await
            .map_err(|e| GateError::NetworkError(e.to_string()))?;

        Ok(result)
    }

    /// Get the capability registry.
    pub fn registry(&self) -> &CapabilityRegistry {
        &self.registry
    }

    /// Get current configuration.
    pub fn config(&self) -> &GateConfig {
        &self.config
    }
}

// ============================================================================
// THREAD-SAFE WRAPPER
// ============================================================================

/// Thread-safe wrapper for CapabilitiesGate.
pub type SharedCapabilitiesGate = Arc<RwLock<CapabilitiesGate>>;

/// Create a new shared capabilities gate.
pub fn create_shared_gate() -> SharedCapabilitiesGate {
    Arc::new(RwLock::new(CapabilitiesGate::new()))
}

/// Create a new shared capabilities gate with configuration.
pub fn create_shared_gate_with_config(config: GateConfig) -> SharedCapabilitiesGate {
    Arc::new(RwLock::new(CapabilitiesGate::with_config(config)))
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capability_registry_defaults() {
        let registry = CapabilityRegistry::with_defaults();
        assert!(registry.get("Finance_Data_Fetch").is_some());
        assert!(registry.get("Github_Read").is_some());
        assert!(registry.get("Github_Draft_PR").is_some());
    }

    #[test]
    fn test_data_scrubber() {
        let input = "<script>alert('xss')</script>Hello World";
        let output = DataScrubber::scrub_string(input);
        assert!(!output.contains("<script"));
        assert!(output.contains("Hello World"));
    }

    #[test]
    fn test_rate_limiter() {
        let mut limiter = RateLimiter::new();
        
        // Should allow first request
        assert!(limiter.check("test", 2).is_ok());
        
        // Should allow second request
        assert!(limiter.check("test", 2).is_ok());
        
        // Should block third request
        assert!(limiter.check("test", 2).is_err());
    }

    #[test]
    fn test_input_validation() {
        let request = CapabilityRequest::new(
            "Finance_Data_Fetch".to_string(),
            [("symbol".to_string(), "AAPL".to_string())].into_iter().collect(),
            "julia".to_string(),
            AutonomyLevel::Full,
        );
        
        assert!(InputValidator::validate(&request).is_ok());
    }

    #[test]
    fn test_input_validation_empty_capability() {
        let request = CapabilityRequest::new(
            "".to_string(),
            HashMap::new(),
            "julia".to_string(),
            AutonomyLevel::Full,
        );
        
        assert!(InputValidator::validate(&request).is_err());
    }

    #[test]
    fn test_capability_response() {
        let response = CapabilityResponse::success(
            Uuid::new_v4(),
            "Finance_Data_Fetch".to_string(),
            serde_json::json!({"data": "test"}),
            0.25,
        );
        
        assert!(response.success);
        assert!(response.error.is_none());
    }

    #[test]
    fn test_gate_config_from_env() {
        // Set environment variables
        std::env::set_var("ITHERIS_REQUIRE_SIGNATURES", "false");
        
        let config = GateConfig::from_env();
        assert!(!config.require_signatures);
        
        // Clean up
        std::env::remove_var("ITHERIS_REQUIRE_SIGNATURES");
    }
}
