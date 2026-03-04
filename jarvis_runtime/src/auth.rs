//! # Authentication
//!
//! JWT authentication and password hashing.

use crate::user::User;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, debug};

/// Auth error types
#[derive(Debug)]
pub enum AuthError {
    InvalidCredentials,
    TokenExpired,
    TokenInvalid,
    UserNotFound,
    PasswordMismatch,
    Unauthorized,
}

impl std::fmt::Display for AuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AuthError::InvalidCredentials => write!(f, "Invalid credentials"),
            AuthError::TokenExpired => write!(f, "Token expired"),
            AuthError::TokenInvalid => write!(f, "Token invalid"),
            AuthError::UserNotFound => write!(f, "User not found"),
            AuthError::PasswordMismatch => write!(f, "Password mismatch"),
            AuthError::Unauthorized => write!(f, "Unauthorized"),
        }
    }
}

impl std::error::Error for AuthError {}

/// JWT claims
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JWTClaims {
    /// User ID
    pub sub: String,
    /// Username
    pub username: String,
    /// Token ID
    pub jti: String,
    /// Issued at
    pub iat: i64,
    /// Expiration
    pub exp: i64,
    /// Capabilities
    pub capabilities: Vec<String>,
}

impl JWTClaims {
    /// Create new claims
    pub fn new(user_id: uuid::Uuid, username: String, capabilities: Vec<String>, validity_secs: i64) -> Self {
        let now = chrono::Utc::now();
        Self {
            sub: user_id.to_string(),
            username,
            jti: uuid::Uuid::new_v4().to_string(),
            iat: now.timestamp(),
            exp: now.timestamp() + validity_secs,
            capabilities,
        }
    }

    /// Check if token is expired
    pub fn is_expired(&self) -> bool {
        chrono::Utc::now().timestamp() > self.exp
    }
}

/// Auth service
pub struct Auth {
    users: Arc<RwLock<Vec<User>>>,
    jwt_secret: String,
    jwt_validity_secs: i64,
}

impl Auth {
    /// Create new auth service
    pub fn new(jwt_secret: String) -> Self {
        Self {
            users: Arc::new(RwLock::new(Vec::new())),
            jwt_secret,
            jwt_validity_secs: 3600, // 1 hour
        }
    }

    /// Register a new user
    pub async fn register(&self, username: String, password: String, email: Option<String>) -> Result<User, Box<dyn std::error::Error + Send + Sync>> {
        let mut users = self.users.write().await;
        
        // Check if user exists
        if users.iter().any(|u| u.username == username) {
            return Err(Box::new(AuthError::InvalidCredentials));
        }
        
        // Hash password
        let password_hash = Self::hash_password(&password)?;
        
        let mut user = User::new(username);
        user.email = email;
        user.set_password(password_hash);
        
        users.push(user.clone());
        
        info!("Registered user: {}", user.username);
        Ok(user)
    }

    /// Authenticate user
    pub async fn authenticate(&self, username: &str, password: &str) -> Result<(User, String), AuthError> {
        let users = self.users.read().await;
        
        let user = users
            .iter()
            .find(|u| u.username == username)
            .ok_or(AuthError::UserNotFound)?;
        
        // Verify password
        if !Self::verify_password(password, user.password_hash.as_ref().ok_or(AuthError::InvalidCredentials)?) {
            return Err(AuthError::PasswordMismatch);
        }
        
        // Generate JWT
        let token = self.generate_token(user).map_err(|_| AuthError::TokenInvalid)?;
        
        Ok((user.clone(), token))
    }

    /// Verify JWT token
    pub fn verify_token(&self, token: &str) -> Result<JWTClaims, AuthError> {
        // In production, use jsonwebtoken crate
        // This is a simplified version for demonstration
        
        let parts: Vec<&str> = token.split('.').collect();
        if parts.len() != 3 {
            return Err(AuthError::TokenInvalid);
        }
        
        // Decode payload (base64)
        let payload = parts[1];
        let decoded = Self::base64_decode(payload);
        
        let claims: JWTClaims = serde_json::from_slice(&decoded)
            .map_err(|_| AuthError::TokenInvalid)?;
        
        if claims.is_expired() {
            return Err(AuthError::TokenExpired);
        }
        
        Ok(claims)
    }

    /// Generate JWT token
    fn generate_token(&self, user: &User) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let capabilities = vec!["read".to_string(), "query".to_string()];
        
        let claims = JWTClaims::new(
            user.id,
            user.username.clone(),
            capabilities,
            self.jwt_validity_secs,
        );
        
        // Serialize claims
        let payload = serde_json::to_vec(&claims)?;
        let encoded = Self::base64_encode(&payload);
        
        // Create token (simplified - in production use proper JWT signing)
        Ok(format!("header.{}.signature", encoded))
    }

    /// Hash password using Argon2
    fn hash_password(password: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        use argon2::{
            password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
            Argon2,
        };
        
        let salt = SaltString::generate(&mut rand::thread_rng());
        let argon2 = Argon2::default();
        
        let hash = argon2.hash_password(password.as_bytes(), &salt)?;
        
        Ok(hash.to_string())
    }

    /// Verify password
    fn verify_password(password: &str, hash: &str) -> bool {
        use argon2::{PasswordHash, PasswordVerifier, Argon2};
        
        let parsed_hash = PasswordHash::new(hash).unwrap();
        Argon2::default().verify_password(password.as_bytes(), &parsed_hash).is_ok()
    }

    /// Base64 encode
    fn base64_encode(data: &[u8]) -> String {
        use base64::{Engine as _, engine::general_purpose::STANDARD};
        STANDARD.encode(data)
    }

    /// Base64 decode
    fn base64_decode(data: &str) -> Vec<u8> {
        use base64::{Engine as _, engine::general_purpose::STANDARD};
        STANDARD.decode(data).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_register_and_authenticate() {
        let auth = Auth::new("secret".to_string());
        
        let user = auth.register("testuser".to_string(), "password123".to_string(), None).await.unwrap();
        assert_eq!(user.username, "testuser");
        
        let (authenticated_user, token) = auth.authenticate("testuser", "password123").await.unwrap();
        assert_eq!(authenticated_user.username, "testuser");
        assert!(!token.is_empty());
    }
}
