//! X.509 SVID (SPIFFE Verifiable Identity Document)
//!
//! This module provides X.509 SVID management for SPIFFE identity.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// X.509 SVID - represents a workload's identity certificate
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct X509Svid {
    /// Certificate in DER format
    certificate: Vec<u8>,
    /// Private key in DER format
    private_key: Vec<u8>,
    /// Certificate chain
    chain: Vec<Vec<u8>>,
    /// Certificate fingerprint
    fingerprint: String,
    /// Not before
    not_before: DateTime<Utc>,
    /// Not after (expiration)
    not_after: DateTime<Utc>,
}

impl X509Svid {
    /// Create a new X.509 SVID
    pub fn new(certificate: Vec<u8>, private_key: Vec<u8>) -> Self {
        let fingerprint = Self::compute_fingerprint(&certificate);
        
        // For mock certificates, use fixed timestamps
        // In production, parse from actual certificate
        let not_before = Utc::now();
        let not_after = Utc::now() + chrono::Duration::hours(24);

        X509Svid {
            certificate,
            private_key,
            chain: vec![],
            fingerprint,
            not_before,
            not_after,
        }
    }

    /// Create with full parameters
    pub fn new_full(
        certificate: Vec<u8>,
        private_key: Vec<u8>,
        chain: Vec<Vec<u8>>,
        not_before: DateTime<Utc>,
        not_after: DateTime<Utc>,
    ) -> Self {
        let fingerprint = Self::compute_fingerprint(&certificate);
        
        X509Svid {
            certificate,
            private_key,
            chain,
            fingerprint,
            not_before,
            not_after,
        }
    }

    /// Compute SHA256 fingerprint of certificate
    fn compute_fingerprint(cert: &[u8]) -> String {
        let mut hasher = Sha256::new();
        hasher.update(cert);
        let result = hasher.finalize();
        hex::encode(result)
    }

    /// Get the certificate
    pub fn certificate(&self) -> &[u8] {
        &self.certificate
    }

    /// Get the private key
    pub fn private_key(&self) -> &[u8] {
        &self.private_key
    }

    /// Get the certificate chain
    pub fn chain(&self) -> &[Vec<u8>] {
        &self.chain
    }

    /// Get the fingerprint
    pub fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    /// Get expiration time
    pub fn expires_at(&self) -> DateTime<Utc> {
        self.not_after
    }

    /// Get not-before time
    pub fn valid_from(&self) -> DateTime<Utc> {
        self.not_before
    }

    /// Check if the SVID is expired
    pub fn is_expired(&self) -> bool {
        Utc::now() > self.not_after
    }

    /// Check if the SVID is not yet valid
    pub fn is_not_yet_valid(&self) -> bool {
        Utc::now() < self.not_before
    }

    /// Check if the SVID is currently valid
    pub fn is_valid(&self) -> bool {
        !self.is_expired() && !self.is_not_yet_valid()
    }

    /// Get remaining validity duration
    pub fn remaining_validity(&self) -> chrono::Duration {
        let now = Utc::now();
        if now >= self.not_after {
            chrono::Duration::zero()
        } else {
            self.not_after.signed_duration_since(now)
        }
    }

    /// Check if SVID needs renewal (less than 5 minutes remaining)
    pub fn needs_renewal(&self) -> bool {
        self.remaining_validity() < chrono::Duration::minutes(5)
    }

    /// Get certificate in PEM format
    pub fn certificate_pem(&self) -> String {
        // Simple PEM encoding for demonstration
        // In production, use a proper X.509 library
        let encoded = base64::encode(&self.certificate);
        format!(
            "-----BEGIN CERTIFICATE-----\n{}\n-----END CERTIFICATE-----",
            encoded
        )
    }

    /// Get private key in PEM format
    pub fn private_key_pem(&self) -> String {
        let encoded = base64::encode(&self.private_key);
        format!(
            "-----BEGIN PRIVATE KEY-----\n{}\n-----END PRIVATE KEY-----",
            encoded
        )
    }
}

/// SVID - trait for different SVID types
pub trait Svid {
    /// Get the SPIFFE ID from the SVID
    fn spiffe_id(&self) -> &str;
    
    /// Get the certificate
    fn certificate(&self) -> &[u8];
    
    /// Get the private key
    fn private_key(&self) -> &[u8];
    
    /// Check if expired
    fn is_expired(&self) -> bool;
}

impl Svid for X509Svid {
    fn spiffe_id(&self) -> &str {
        // In production, parse from certificate
        // For now, return a placeholder
        "spiffe://warden-mesh/agent"
    }
    
    fn certificate(&self) -> &[u8] {
        &self.certificate
    }
    
    fn private_key(&self) -> &[u8] {
        &self.private_key
    }
    
    fn is_expired(&self) -> bool {
        self.is_expired()
    }
}

/// X.509 Trust Bundle
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct X509Bundle {
    /// Trust domain
    trust_domain: String,
    /// Certificates in the bundle
    certificates: Vec<X509Certificate>,
    /// Refresh hint (when to refresh the bundle)
    refresh_hint: Option<DateTime<Utc>>,
}

impl X509Bundle {
    /// Create a new X.509 bundle
    pub fn new(trust_domain: String, certificates: Vec<X509Certificate>) -> Self {
        X509Bundle {
            trust_domain,
            certificates,
            refresh_hint: None,
        }
    }

    /// Get trust domain
    pub fn trust_domain(&self) -> &str {
        &self.trust_domain
    }

    /// Get certificates
    pub fn certificates(&self) -> &[X509Certificate] {
        &self.certificates
    }

    /// Add a certificate to the bundle
    pub fn add_certificate(&mut self, cert: X509Certificate) {
        self.certificates.push(cert);
    }
}

/// X.509 Certificate representation
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct X509Certificate {
    /// Certificate data
    data: Vec<u8>,
    /// Subject (who it's issued to)
    subject: String,
    /// Issuer (who issued it)
    issuer: String,
    /// Not before
    not_before: DateTime<Utc>,
    /// Not after
    not_after: DateTime<Utc>,
    /// Serial number
    serial: String,
}

impl X509Certificate {
    /// Create a new certificate
    pub fn new(
        data: Vec<u8>,
        subject: String,
        issuer: String,
        not_before: DateTime<Utc>,
        not_after: DateTime<Utc>,
        serial: String,
    ) -> Self {
        X509Certificate {
            data,
            subject,
            issuer,
            not_before,
            not_after,
            serial,
        }
    }

    /// Get certificate data
    pub fn data(&self) -> &[u8] {
        &self.data
    }

    /// Get subject
    pub fn subject(&self) -> &str {
        &self.subject
    }

    /// Get issuer
    pub fn issuer(&self) -> &str {
        &self.issuer
    }

    /// Get expiration
    pub fn expires_at(&self) -> DateTime<Utc> {
        self.not_after
    }

    /// Check if expired
    pub fn is_expired(&self) -> bool {
        Utc::now() > self.not_after
    }

    /// Get serial number
    pub fn serial(&self) -> &str {
        &self.serial
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_svid_creation() {
        let cert = vec![0u8; 64];
        let key = vec![0u8; 32];
        
        let svid = X509Svid::new(cert.clone(), key.clone());
        
        assert_eq!(svid.certificate(), &cert);
        assert_eq!(svid.private_key(), &key);
        assert!(!svid.is_expired());
    }

    #[test]
    fn test_svid_validity() {
        let svid = X509Svid::new(vec![0u8; 64], vec![0u8; 32]);
        
        assert!(svid.is_valid());
        assert!(!svid.is_expired());
        assert!(!svid.is_not_yet_valid());
    }

    #[test]
    fn test_svid_renewal() {
        let svid = X509Svid::new(vec![0u8; 64], vec![0u8; 32]);
        
        // Newly created SVID should not need renewal
        assert!(!svid.needs_renewal());
    }

    #[test]
    fn test_fingerprint() {
        let cert = vec![1u8, 2u8, 3u8, 4u8];
        let svid1 = X509Svid::new(cert.clone(), vec![0u8; 32]);
        let svid2 = X509Svid::new(cert, vec![0u8; 32]);
        
        // Same certificate should produce same fingerprint
        assert_eq!(svid1.fingerprint(), svid2.fingerprint());
    }

    #[test]
    fn test_bundle() {
        let mut bundle = X509Bundle::new(
            "warden-mesh".to_string(),
            vec![],
        );
        
        let cert = X509Certificate::new(
            vec![0u8; 64],
            "CN=test".to_string(),
            "CN=issuer".to_string(),
            Utc::now(),
            Utc::now() + chrono::Duration::days(365),
            "12345".to_string(),
        );
        
        bundle.add_certificate(cert.clone());
        
        assert_eq!(bundle.certificates().len(), 1);
        assert_eq!(bundle.trust_domain(), "warden-mesh");
    }
}
