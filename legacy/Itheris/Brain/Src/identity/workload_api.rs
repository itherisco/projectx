//! Workload API Client for SPIFFE
//!
//! Implements the SPIFFE Workload API for fetching X.509 SVIDs and trust bundles.
//! The Workload API is typically exposed via a Unix domain socket.

use crate::identity::spiffe_identity::{SpiffeError, SpiffeId, SpiffeIdentity, X509Svid};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Workload API endpoint configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkloadApiConfig {
    pub socket_path: String,
    pub timeout_ms: u64,
    pub retry_attempts: u32,
}

impl Default for WorkloadApiConfig {
    fn default() -> Self {
        WorkloadApiConfig {
            socket_path: "/tmp/spire-agent/public/api/workload".to_string(),
            timeout_ms: 5000,
            retry_attempts: 3,
        }
    }
}

/// Workload API response types
#[derive(Debug, Serialize, Deserialize)]
pub struct FetchX509SvidResponse {
    pub svids: Vec<X509SvidJson>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct X509SvidJson {
    pub spiffe_id: String,
    pub x509_svid: String,
    pub x509_svid_key: String,
    pub bundle: String,
}

/// Workload API Client for fetching SVIDs
pub struct WorkloadApiClient {
    config: WorkloadApiConfig,
    cached_svid: RwLock<Option<CachedSvid>>,
    client: reqwest::Client,
}

/// Cached SVID with expiry
#[derive(Clone)]
struct CachedSvid {
    identity: SpiffeIdentity,
    cached_at: DateTime<Utc>,
}

impl WorkloadApiClient {
    /// Create a new Workload API client
    pub fn new(config: WorkloadApiConfig) -> Self {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(config.timeout_ms))
            .build()
            .expect("Failed to create HTTP client");

        WorkloadApiClient {
            config,
            cached_svid: RwLock::new(None),
            client,
        }
    }

    /// Create with default configuration
    pub fn default_client() -> Self {
        Self::new(WorkloadApiConfig::default())
    }

    /// Fetch X.509 SVID for a given SPIFFE ID
    pub async fn fetch_svid(&self, spiffe_id: &SpiffeId) -> Result<SpiffeError, SpiffeError> {
        // Check cache first
        {
            let cache = self.cached_svid.read().await;
            if let Some(cached) = cache.as_ref() {
                if cached.identity.spiffe_id == *spiffe_id {
                    // Check if cache is still valid (less than 5 minutes old)
                    let age = Utc::now().signed_duration_since(cached.cached_at);
                    if age.num_minutes() < 5 {
                        return Ok(cached.identity.clone());
                    }
                }
            }
        }

        // Fetch from Workload API
        let identity = self.fetch_from_api(spiffe_id).await?;

        // Update cache
        {
            let mut cache = self.cached_svid.write().await;
            *cache = Some(CachedSvid {
                identity: identity.clone(),
                cached_at: Utc::now(),
            });
        }

        Ok(identity)
    }

    /// Fetch from the Workload API
    async fn fetch_from_api(&self, spiffe_id: &SpiffeId) -> Result<SpiffeIdentity, SpiffeError> {
        // In a real implementation, this would connect to the SPIRE agent's
        // Workload API via Unix domain socket or gRPC
        // For now, we simulate the response

        // Build the Workload API URL
        let url = format!(
            "http://localhost/{}/fetch",
            self.config.socket_path
        );

        // Simulate SVID generation (in production, this would be real)
        let x509_svid = X509Svid::new(
            self.generate_mock_cert(spiffe_id),
            self.generate_mock_key(),
        );

        // Create trust bundle (in production, fetch from API)
        let bundle = self.generate_mock_bundle();

        // Create federated bundles
        let mut federated_bundles = HashMap::new();
        federated_bundles.insert("external-trust-domain".to_string(), self.generate_mock_bundle());

        let identity = SpiffeIdentity::new(
            spiffe_id.clone(),
            x509_svid,
            bundle,
            federated_bundles,
            3600, // 1 hour validity
        );

        Ok(identity)
    }

    /// Fetch trust bundle for a trust domain
    pub async fn fetch_trust_bundle(&self, trust_domain: &str) -> Result<Vec<u8>, SpiffeError> {
        // In production, fetch from Workload API
        Ok(self.generate_mock_bundle())
    }

    /// Fetch all X.509 bundles
    pub async fn fetch_bundles(&self) -> Result<HashMap<String, Vec<u8>>, SpiffeError> {
        // In production, fetch from Workload API
        let mut bundles = HashMap::new();
        bundles.insert("warden-mesh".to_string(), self.generate_mock_bundle());
        Ok(bundles)
    }

    /// Generate mock certificate (for testing)
    fn generate_mock_cert(&self, spiffe_id: &SpiffeId) -> Vec<u8> {
        // Generate a mock X.509 certificate
        // In production, this would be the actual certificate from the Workload API
        let cert_pem = format!(
            "-----BEGIN CERTIFICATE-----\nMIIBkTCB+wIJAMZw2qKq3O3DMA0GCSqGSIb3DQEBCwUAMBExDzANBgNVBAMMBndh\ncmRlbi1tZXNoMDAeFw0yMzAxMDEwMDAwMDBaFw0yNDAxMDEwMDAwMDBaMBExDzAN\nBgNVBAMMBndhcmRlbi1tZXNoMDBcMA0GCSqGSIb3DQEBAQUAA0sAMEgCQQCo2HH9D\n{}-----END CERTIFICATE-----\n",
            spiffe_id
        );
        cert_pem.as_bytes().to_vec()
    }

    /// Generate mock private key (for testing)
    fn generate_mock_key(&self) -> Vec<u8> {
        // Generate a mock private key
        let key_pem = "-----BEGIN PRIVATE KEY-----\nMIIBVQIBADANBgkqhkiG9w0BAQEFAASCAT4wggE6AgEAAkEAqNhx/Q2jG9XZz0j+\n{}-----END PRIVATE KEY-----\n".as_bytes().to_vec();
        key_pem
    }

    /// Generate mock trust bundle (for testing)
    fn generate_mock_bundle(&self) -> Vec<u8> {
        let bundle_pem = "-----BEGIN CERTIFICATE-----\nMIIBkTCB+wIJAMZw2qKq3O3DMA0GCSqGSIb3DQEBCwUAMBExDzANBgNVBAMMBndh\ncmRlbi1tZXNoMDAeFw0yMzAxMDEwMDAwMDBaFw0yNDAxMDEwMDAwMDBaMBExDzAN\nBgNVBAMMBndhcmRlbi1tZXNoMDBcMA0GCSqGSIb3DQEBAQUAA0sAMEgCQQCo2HH9D\n{}-----END CERTIFICATE-----\n".as_bytes().to_vec();
        bundle_pem
    }

    /// Invalidate the cache
    pub async fn invalidate_cache(&self) {
        let mut cache = self.cached_svid.write().await;
        *cache = None;
    }

    /// Get current cache status
    pub async fn is_cached(&self) -> bool {
        let cache = self.cached_svid.read().await;
        cache.is_some()
    }
}

impl Default for WorkloadApiClient {
    fn default() -> Self {
        Self::default_client()
    }
}
