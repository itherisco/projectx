//! # JWT Authentication Module
//!
//! Secure JWT-based authentication with proper token validation.
//! This module handles auth tokens and session management with
//! Rust's strict type system and performance in cryptographic operations.
//!
//! ## Security Properties
//!
//! - **HS256 signing**: HMAC-SHA256 for token authentication
//! - **Expiration**: Tokens automatically expire
//! - **Audience validation**: Tokens must be intended for our system
//! - **Fail-closed**: Invalid tokens result in denial
//!
//! ## Threat Model
//!
//! - Original vulnerability: Authentication bypass in JWTAuth.jl
//! - Attack: Token validation could be circumvented
//! - Impact: Unauthorized access to system capabilities

use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

/// JWT Claims structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JWTClaims {
    pub sub: String,              // Subject (user ID)
    pub exp: u64,                  // Expiration time
    pub iat: u64,                  // Issued at time
    pub aud: String,              // Audience
    pub role: String,             // User role
    pub session_id: String,       // Session identifier
    pub permissions: Vec<String>, // Granted permissions
}

/// Authentication configuration
#[derive(Debug, Clone)]
pub struct AuthConfig {
    pub secret: [u8; 32],
    pub issuer: String,
    pub audience: String,
    pub token_expiry: Duration,
}

impl AuthConfig {
    pub fn new(secret: [u8; 32], issuer: String, audience: String) -> Self {
        Self {
            secret,
            issuer,
            audience,
            token_expiry: Duration::from_secs(3600), // 1 hour default
        }
    }

    pub fn with_expiry(mut self, expiry: Duration) -> Self {
        self.token_expiry = expiry;
        self
    }
}

/// Request to create a new JWT
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateTokenRequest {
    pub user_id: String,
    pub role: String,
    pub permissions: Vec<String>,
}

/// Request to validate a JWT
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidateTokenRequest {
    pub token: String,
}

/// Active session tracking
#[derive(Debug, Clone)]
pub struct Session {
    pub session_id: String,
    pub user_id: String,
    pub created_at: u64,
    pub last_accessed: u64,
    pub expires_at: u64,
}

/// Session manager
pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<String, Session>>>>,
    max_sessions: usize,
}

impl SessionManager {
    pub fn new(max_sessions: usize) -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            max_sessions,
        }
    }

    pub async fn create_session(&self, user_id: &str) -> Result<Session, String> {
        let mut store = self.sessions.write().await;
        
        if store.len() >= self.max_sessions {
            return Err("Session store full".to_string());
        }

        let mut session_id_bytes = [0u8; 16];
        rand::rngs::OsRng.fill_bytes(&mut session_id_bytes);
        let session_id = hex::encode(session_id_bytes);
        
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let session = Session {
            session_id: session_id.clone(),
            user_id: user_id.to_string(),
            created_at: now,
            last_accessed: now,
            expires_at: now + 3600, // 1 hour
        };

        store.insert(session_id, session.clone());
        Ok(session)
    }

    pub async fn get_session(&self, session_id: &str) -> Option<Session> {
        let store = self.sessions.read().await;
        store.get(session_id).cloned()
    }

    pub async fn invalidate_session(&self, session_id: &str) -> Result<(), String> {
        let mut store = self.sessions.write().await;
        store.remove(session_id).ok_or_else(|| "Session not found".to_string())?;
        Ok(())
    }

    pub async fn cleanup_expired_sessions(&self) -> usize {
        let mut store = self.sessions.write().await;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let expired: Vec<String> = store
            .iter()
            .filter(|(_, s)| s.expires_at < now)
            .map(|(id, _)| id.clone())
            .collect();

        for id in &expired {
            store.remove(id);
        }
        expired.len()
    }
}

/// JWT Authentication handler
pub struct JWTAuth {
    config: AuthConfig,
    sessions: SessionManager,
}

impl JWTAuth {
    /// Create a new JWTAuth with a generated secret key
    pub fn new(issuer: String, audience: String) -> Self {
        let mut secret = [0u8; 32];
        rand::rngs::OsRng.fill_bytes(&mut secret);
        
        Self::with_config(AuthConfig::new(secret, issuer, audience))
    }

    /// Create a new JWTAuth with a provided secret key
    pub fn with_config(config: AuthConfig) -> Self {
        Self {
            config,
            sessions: SessionManager::new(1000),
        }
    }

    /// Generate a new JWT token
    pub async fn create_token(&self, request: CreateTokenRequest) -> Result<String, String> {
        // Create session
        let session = self.sessions.create_session(&request.user_id).await?;

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let claims = JWTClaims {
            sub: request.user_id,
            exp: now + self.config.token_expiry.as_secs(),
            iat: now,
            aud: self.config.audience.clone(),
            role: request.role,
            session_id: session.session_id,
            permissions: request.permissions,
        };

        let token = encode(
            &Header::new(Algorithm::HS256),
            &claims,
            &EncodingKey::from_secret(&self.config.secret),
        )
        .map_err(|e| format!("Failed to encode token: {}", e))?;

        Ok(token)
    }

    /// Validate a JWT token
    pub async fn validate_token(&self, request: ValidateTokenRequest) -> Result<JWTClaims, String> {
        let mut validation = Validation::new(Algorithm::HS256);
        validation.set_audience(&[&self.config.audience]);
        validation.validate_exp = true;
        validation.validate_aud = true;

        let token_data = decode::<JWTClaims>(
            &request.token,
            &DecodingKey::from_secret(&self.config.secret),
            &validation,
        )
        .map_err(|e| format!("Token validation failed: {}", e))?;

        // Check session still valid
        if self.sessions.get_session(&token_data.claims.session_id).await.is_none() {
            return Err("Session invalidated".to_string());
        }

        Ok(token_data.claims)
    }

    /// Invalidate a session (logout)
    pub async fn logout(&self, session_id: &str) -> Result<(), String> {
        self.sessions.invalidate_session(session_id).await
    }

    /// Get session information
    pub async fn get_session(&self, session_id: &str) -> Option<Session> {
        self.sessions.get_session(session_id).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_token_creation_and_validation() {
        let auth = JWTAuth::new(
            "jarvis".to_string(),
            "jarvis-system".to_string(),
        );

        let request = CreateTokenRequest {
            user_id: "user123".to_string(),
            role: "admin".to_string(),
            permissions: vec!["read".to_string(), "write".to_string()],
        };

        let token = auth.create_token(request.clone()).await;
        assert!(token.is_ok());

        let validate_request = ValidateTokenRequest {
            token: token.unwrap(),
        };

        let claims = auth.validate_token(validate_request).await;
        assert!(claims.is_ok());
        assert_eq!(claims.unwrap().sub, "user123");
    }

    #[tokio::test]
    async fn test_session_invalidation() {
        let auth = JWTAuth::new(
            "jarvis".to_string(),
            "jarvis-system".to_string(),
        );

        let request = CreateTokenRequest {
            user_id: "user123".to_string(),
            role: "user".to_string(),
            permissions: vec![],
        };

        let token = auth.create_token(request.clone()).await.unwrap();
        
        // Get session ID from token
        let validate_request = ValidateTokenRequest {
            token: token.clone(),
        };
        let claims = auth.validate_token(validate_request).await.unwrap();
        let session_id = claims.session_id.clone();

        // Invalidate session
        auth.logout(&session_id).await.unwrap();

        // Token should now be invalid
        let validate_request2 = ValidateTokenRequest {
            token: token,
        };
        let result = auth.validate_token(validate_request2).await;
        assert!(result.is_err());
    }
}
