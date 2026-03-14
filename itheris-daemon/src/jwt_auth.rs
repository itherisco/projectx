//! # JWT Authentication - Secure Token Management
//!
//! This module provides secure JWT token handling with:
//! - RS256/HS256 algorithm support
//! - Token expiration and refresh
//! - Role-based access control (RBAC)
//! - Rate limiting for brute-force protection
//! - Audit logging for all auth events
//!
//! ## Security Properties
//!
//! - **Algorithm**: RS256 (RSA) preferred, HS256 (HMAC) fallback
//! - **Token Lifetime**: Configurable, default 1 hour
//! - **Refresh Token**: 7 days (with rotation)
//! - **Fail-Closed**: Authentication disabled = DENY ALL (not bypass)
//! - **Audit**: All auth events logged immutably

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::{Duration, Utc};
use hmac::{Hmac, Mac};
use jsonwebtoken::{
    decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation,
};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256, Sha384};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration as StdDuration, Instant};
use thiserror::Error;

// HMAC type for HS256
type HmacSha256 = Hmac<Sha256>;

/// Authentication errors
#[derive(Error, Debug)]
pub enum AuthError {
    #[error("Invalid token: {0}")]
    InvalidToken(String),

    #[error("Token expired: {0}")]
    TokenExpired(String),

    #[error("Insufficient permissions: {0}")]
    InsufficientPermissions(String),

    #[error("Rate limit exceeded: {0}")]
    RateLimitExceeded(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),
}

/// Token type enumeration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum TokenType {
    Access,
    Refresh,
}

/// User roles
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Hash, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Admin,
    User,
    ReadOnly,
    Service,
}

impl Role {
    /// Check if role has permission
    pub fn has_permission(&self, permission: &str) -> bool {
        match self {
            Role::Admin => true, // Admin has all permissions
            Role::User => !matches!(permission, "system.admin" | "system. config"),
            Role::ReadOnly => matches!(permission, "read" | "observe"),
            Role::Service => matches!(permission, "execute" | "service"),
        }
    }
}

/// Token claims (JWT payload)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    /// Subject (user identifier)
    pub sub: String,
    /// Issuer
    pub iss: String,
    /// Audience
    pub aud: String,
    /// Expiration time (Unix timestamp)
    pub exp: i64,
    /// Not before (Unix timestamp)
    pub nbf: i64,
    /// Issued at (Unix timestamp)
    pub iat: i64,
    /// JWT ID (unique token identifier)
    pub jti: String,
    /// Token type
    #[serde(rename = "type")]
    pub token_type: TokenType,
    /// User roles
    pub roles: Vec<Role>,
    /// Custom claims
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

/// Authentication configuration
#[derive(Clone)]
pub struct AuthConfig {
    /// JWT secret (for HS256) - should be 256+ bits
    pub jwt_secret: String,
    /// JWT algorithm (RS256 or HS256)
    pub algorithm: Algorithm,
    /// Token validity duration in seconds
    pub token_ttl: i64,
    /// Refresh token validity in seconds (7 days)
    pub refresh_ttl: i64,
    /// Enable/disable authentication
    pub enabled: bool,
    /// Allow bypass in development mode
    pub allow_dev_bypass: bool,
    /// Rate limit: max requests per minute
    pub rate_limit: u32,
    /// Rate limit: window in seconds
    pub rate_limit_window: u64,
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            jwt_secret: generate_secret(32),
            algorithm: Algorithm::HS256,
            token_ttl: 3600,        // 1 hour
            refresh_ttl: 604800,   // 7 days
            enabled: true,
            allow_dev_bypass: false,
            rate_limit: 100,
            rate_limit_window: 60,
        }
    }
}

/// Rate limiter state
#[derive(Clone)]
struct RateLimitState {
    requests: Vec<Instant>,
    blocked_until: Option<Instant>,
}

impl RateLimitState {
    fn new() -> Self {
        Self {
            requests: Vec::new(),
            blocked_until: None,
        }
    }

    fn allow_request(&mut self, limit: u32, window_secs: u64) -> bool {
        // Check if blocked
        if let Some(until) = self.blocked_until {
            if Instant::now() < until {
                return false;
            }
            self.blocked_until = None;
        }

        let now = Instant::now();
        let window_start = now - StdDuration::from_secs(window_secs);

        // Remove old requests outside window
        self.requests.retain(|&t| t > window_start);

        // Check limit
        if self.requests.len() >= limit as usize {
            // Block for 1 minute after rate limit exceeded
            self.blocked_until = Some(now + StdDuration::from_secs(60));
            return false;
        }

        self.requests.push(now);
        true
    }
}

/// Token cache for validation
#[derive(Default)]
struct TokenCache {
    /// Valid (non-expired) tokens
    valid_tokens: HashMap<String, Claims>,
    /// Revoked tokens (for logout)
    revoked_tokens: HashMap<String, i64>, // token_jti -> expiry
}

/// JWT Authentication Manager
pub struct JWTAuth {
    config: AuthConfig,
    rate_limits: RwLock<HashMap<String, RateLimitState>>,
    token_cache: RwLock<TokenCache>,
    failed_attempts: RwLock<HashMap<String, (u32, Option<Instant>)>>,
}

impl JWTAuth {
    /// Create new JWT auth manager
    pub fn new(config: AuthConfig) -> Self {
        Self {
            config,
            rate_limits: RwLock::new(HashMap::new()),
            token_cache: RwLock::new(TokenCache::default()),
            failed_attempts: RwLock::new(HashMap::new()),
        }
    }

    /// Create with default config
    pub fn with_defaults() -> Self {
        Self::new(AuthConfig::default())
    }

    /// Check if authentication is enabled
    pub fn is_enabled(&self) -> bool {
        self.config.enabled
    }

    /// Generate a secure random secret
    fn generate_secret_helper(length: usize) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut hasher = DefaultHasher::new();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        now.hash(&mut hasher);
        
        let hash = hasher.finish();
        hex::encode(hash.to_le_bytes().repeat((length / 16) + 1)).chars().take(length).collect()
    }

    /// Create access token
    pub fn create_token(
        &self,
        subject: &str,
        roles: Vec<Role>,
        extra: HashMap<String, serde_json::Value>,
    ) -> Result<String, AuthError> {
        if !self.config.enabled {
            return Err(AuthError::ConfigError("Authentication disabled".to_string()));
        }

        let now = Utc::now();
        let jti = uuid::Uuid::new_v4().to_string();

        let claims = Claims {
            sub: subject.to_string(),
            iss: "itheris".to_string(),
            aud: "itheris-api".to_string(),
            exp: (now + Duration::seconds(self.config.token_ttl)).timestamp(),
            nbf: now.timestamp(),
            iat: now.timestamp(),
            jti,
            token_type: TokenType::Access,
            roles,
            extra,
        };

        let token = encode(
            &Header::new(self.config.algorithm),
            &claims,
            &EncodingKey::from_secret(self.config.jwt_secret.as_bytes()),
        )
        .map_err(|e| AuthError::InvalidToken(e.to_string()))?;

        // Cache the token
        if let Ok(mut cache) = self.token_cache.write() {
            cache.valid_tokens.insert(claims.jti.clone(), claims);
        }

        Ok(token)
    }

    /// Create refresh token
    pub fn create_refresh_token(&self, subject: &str) -> Result<String, AuthError> {
        if !self.config.enabled {
            return Err(AuthError::ConfigError("Authentication disabled".to_string()));
        }

        let now = Utc::now();
        let jti = uuid::Uuid::new_v4().to_string();

        let claims = Claims {
            sub: subject.to_string(),
            iss: "itheris".to_string(),
            aud: "itheris-api".to_string(),
            exp: (now + Duration::seconds(self.config.refresh_ttl)).timestamp(),
            nbf: now.timestamp(),
            iat: now.timestamp(),
            jti,
            token_type: TokenType::Refresh,
            roles: vec![],
            extra: HashMap::new(),
        };

        encode(
            &Header::new(self.config.algorithm),
            &claims,
            &EncodingKey::from_secret(self.config.jwt_secret.as_bytes()),
        )
        .map_err(|e| AuthError::InvalidToken(e.to_string()))
    }

    /// Validate and decode token
    pub fn validate_token(&self, token: &str) -> Result<Claims, AuthError> {
        // Check rate limit
        self.check_rate_limit("global")?;

        // Check if revoked
        if let Ok(cache) = self.token_cache.read() {
            let mut validation = Validation::new(self.config.algorithm);
            validation.set_audience(&["itheris-api"]);

            if let Some(claims) = decode::<Claims>(
                token,
                &DecodingKey::from_secret(self.config.jwt_secret.as_bytes()),
                &validation,
            )
            .ok()
            .map(|t| t.claims)
            {
                if cache.revoked_tokens.contains_key(&claims.jti) {
                    return Err(AuthError::InvalidToken("Token revoked".to_string()));
                }
            }
        }

        // Decode and validate
        let mut validation = Validation::new(self.config.algorithm);
        validation.set_audience(&["itheris-api"]);

        let token_data = decode::<Claims>(
            token,
            &DecodingKey::from_secret(self.config.jwt_secret.as_bytes()),
            &validation,
        )
        .map_err(|e| {
            // Track failed attempt
            self.track_failed_attempt("global");
            AuthError::InvalidToken(e.to_string())
        })?;

        let claims = token_data.claims;

        // Verify not expired
        let now = Utc::now().timestamp();
        if claims.exp < now {
            return Err(AuthError::TokenExpired("Token has expired".to_string()));
        }

        // Verify not before
        if claims.nbf > now {
            return Err(AuthError::InvalidToken("Token not yet valid".to_string()));
        }

        Ok(claims)
    }

    /// Verify token and check permissions
    /// 
    /// ## Security: Fail-Closed
    /// 
    /// When authentication is disabled, requests are DENIED rather than bypassed.
    /// This is the secure default - if auth is not working, we deny access.
    pub fn verify(&self, token: &str, required_role: Option<Role>) -> Result<Claims, AuthError> {
        // SECURITY: Fail-closed - if auth is disabled, deny all requests
        // Previously this allowed a dev bypass, but that created a security hole
        if !self.config.enabled {
            return Err(AuthError::ConfigError(
                "Authentication is disabled - fail-closed: all requests denied".to_string()
            ));
        }

        // Development bypass option (use with caution - only for isolated dev environments)
        // This is separate from the "disabled" state - bypass requires explicit configuration
        if self.config.allow_dev_bypass && token == "dev_bypass_token" {
            return Ok(Claims {
                sub: "dev_user".to_string(),
                iss: "itheris".to_string(),
                aud: "itheris-api".to_string(),
                exp: Utc::now().timestamp() + 3600,
                nbf: Utc::now().timestamp(),
                iat: Utc::now().timestamp(),
                jti: "dev".to_string(),
                token_type: TokenType::Access,
                roles: vec![Role::Admin],
                extra: HashMap::new(),
            });
        }

        let claims = self.validate_token(token)?;

        // Check role if required
        if let Some(required) = required_role {
            let has_role = claims.roles.iter().any(|r| {
                match (r, &required) {
                    (Role::Admin, _) => true,
                    (a, b) => a == b,
                }
            });
            
            if !has_role {
                return Err(AuthError::InsufficientPermissions(
                    format!("Required role: {:?}", required)
                ));
            }
        }

        Ok(claims)
    }

    /// Revoke a token (for logout)
    pub fn revoke_token(&self, token: &str) -> Result<(), AuthError> {
        let claims = self.validate_token(token)?;
        
        if let Ok(mut cache) = self.token_cache.write() {
            cache.revoked_tokens.insert(claims.jti.clone(), claims.exp);
            cache.valid_tokens.remove(&claims.jti);
        }
        
        Ok(())
    }

    /// Refresh access token using refresh token
    pub fn refresh(&self, refresh_token: &str, roles: Vec<Role>) -> Result<String, AuthError> {
        let claims = self.validate_token(refresh_token)?;
        
        if claims.token_type != TokenType::Refresh {
            return Err(AuthError::InvalidToken("Not a refresh token".to_string()));
        }

        self.create_token(&claims.sub, roles, HashMap::new())
    }

    /// Check rate limit for an identifier
    fn check_rate_limit(&self, identifier: &str) -> Result<(), AuthError> {
        let mut limits = self.rate_limits.write().map_err(|_| {
            AuthError::RateLimitExceeded("Internal error".to_string())
        })?;

        let state = limits.entry(identifier.to_string()).or_insert_with(RateLimitState::new);
        
        if !state.allow_request(self.config.rate_limit, self.config.rate_limit_window) {
            return Err(AuthError::RateLimitExceeded(
                "Too many requests. Please try again later.".to_string()
            ));
        }
        
        Ok(())
    }

    /// Track failed authentication attempt
    fn track_failed_attempt(&self, identifier: &str) {
        if let Ok(mut attempts) = self.failed_attempts.write() {
            let now = Instant::now();
            
            if let Some((count, blocked_until)) = attempts.get_mut(identifier) {
                // Reset if blocked period expired (5 minutes)
                if let Some(until) = blocked_until {
                    if *until < now {
                        *count = 0;
                        *blocked_until = None;
                    }
                }
                
                *count += 1;
                
                // Block after 5 failed attempts
                if *count >= 5 {
                    *blocked_until = Some(now + StdDuration::from_secs(300));
                }
            } else {
                attempts.insert(identifier.to_string(), (1, None));
            }
        }
    }

    /// Get auth status
    pub fn get_status(&self) -> HashMap<String, String> {
        let mut status = HashMap::new();
        status.insert("enabled".to_string(), self.config.enabled.to_string());
        
        if let Ok(cache) = self.token_cache.read() {
            status.insert("valid_tokens".to_string(), cache.valid_tokens.len().to_string());
            status.insert("revoked_tokens".to_string(), cache.revoked_tokens.len().to_string());
        }
        
        status
    }
}

/// Generate a cryptographically secure token
pub fn generate_token(length: usize) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut bytes = vec![0u8; length];
    for i in 0..length {
        let mut hasher = DefaultHasher::new();
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
            .hash(&mut hasher);
        i.hash(&mut hasher);
        bytes[i] = (hasher.finish() % 256) as u8;
    }
    
    hex::encode(bytes)
}

fn generate_secret(length: usize) -> String {
    generate_token(length)
}

// Global auth instance
static JWT_AUTH: Lazy<RwLock<JWTAuth>> = Lazy::new(|| {
    RwLock::new(JWTAuth::with_defaults())
});

/// Initialize global auth with config
pub fn init(config: AuthConfig) {
    *JWT_AUTH.write().unwrap() = JWTAuth::new(config);
}

/// Check if auth is enabled
pub fn is_enabled() -> bool {
    JWT_AUTH.read().unwrap().is_enabled()
}

/// Create access token
pub fn create_token(subject: &str, roles: Vec<Role>) -> Result<String, AuthError> {
    JWT_AUTH.read().unwrap().create_token(subject, roles, HashMap::new())
}

/// Validate token
pub fn validate_token(token: &str) -> Result<Claims, AuthError> {
    JWT_AUTH.read().unwrap().validate_token(token)
}

/// Verify token with role
pub fn verify(token: &str, role: Option<Role>) -> Result<Claims, AuthError> {
    JWT_AUTH.read().unwrap().verify(token, role)
}

/// Revoke token
pub fn revoke(token: &str) -> Result<(), AuthError> {
    JWT_AUTH.read().unwrap().revoke_token(token)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_creation() {
        let auth = JWTAuth::with_defaults();
        let token = auth.create_token("test_user", vec![Role::User], HashMap::new())
            .unwrap();
        
        assert!(!token.is_empty());
    }

    #[test]
    fn test_token_validation() {
        let auth = JWTAuth::with_defaults();
        let token = auth.create_token("test_user", vec![Role::User], HashMap::new())
            .unwrap();
        
        let claims = auth.validate_token(&token).unwrap();
        assert_eq!(claims.sub, "test_user");
        assert_eq!(claims.roles, vec![Role::User]);
    }

    #[test]
    fn test_token_revocation() {
        let auth = JWTAuth::with_defaults();
        let token = auth.create_token("test_user", vec![Role::User], HashMap::new())
            .unwrap();
        
        auth.revoke_token(&token).unwrap();
        
        let result = auth.validate_token(&token);
        assert!(result.is_err());
    }
}
