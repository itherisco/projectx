//! # Session Management
//!
//! User session management with expiration and isolation.

use crate::user::User;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, debug};

/// Session error types
#[derive(Debug)]
pub enum SessionError {
    NotFound,
    Expired,
    InvalidToken,
    UserMismatch,
}

impl std::fmt::Display for SessionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SessionError::NotFound => write!(f, "Session not found"),
            SessionError::Expired => write!(f, "Session expired"),
            SessionError::InvalidToken => write!(f, "Invalid session token"),
            SessionError::UserMismatch => write!(f, "User mismatch"),
        }
    }
}

impl std::error::Error for SessionError {}

/// Session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    /// Session ID
    pub id: uuid::Uuid,
    /// User ID
    pub user_id: uuid::Uuid,
    /// Session token (JWT)
    pub token: String,
    /// When session was created
    pub created_at: chrono::DateTime<chrono::Utc>,
    /// When session expires
    pub expires_at: chrono::DateTime<chrono::Utc>,
    /// Last activity timestamp
    pub last_activity: chrono::DateTime<chrono::Utc>,
    /// Session metadata
    pub metadata: HashMap<String, String>,
    /// Whether session is active
    pub is_active: bool,
}

impl Session {
    /// Create new session
    pub fn new(user_id: uuid::Uuid, token: String, validity_secs: i64) -> Self {
        let now = chrono::Utc::now();
        Self {
            id: uuid::Uuid::new_v4(),
            user_id,
            token,
            created_at: now,
            expires_at: now + chrono::Duration::seconds(validity_secs),
            last_activity: now,
            metadata: HashMap::new(),
            is_active: true,
        }
    }

    /// Check if session is valid
    pub fn is_valid(&self) -> bool {
        self.is_active && chrono::Utc::now() < self.expires_at
    }

    /// Extend session
    pub fn extend(&mut self, additional_secs: i64) {
        let now = chrono::Utc::now();
        self.last_activity = now;
        self.expires_at = now + chrono::Duration::seconds(additional_secs);
    }

    /// Invalidate session
    pub fn invalidate(&mut self) {
        self.is_active = false;
    }
}

/// Session manager
pub struct SessionManager {
    sessions: Arc<RwLock<HashMap<uuid::Uuid, Session>>>,
    session_timeout_secs: i64,
}

impl SessionManager {
    /// Create new session manager
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            session_timeout_secs: 3600, // 1 hour default
        }
    }

    /// Create new session for user
    pub async fn create_session(&self, user_id: uuid::Uuid, token: String) -> Session {
        let session = Session::new(user_id, token, self.session_timeout_secs);
        let session_clone = session.clone();
        
        let mut sessions = self.sessions.write().await;
        sessions.insert(session.id, session);
        
        info!("Created session {} for user {}", session_clone.id, user_id);
        session_clone
    }

    /// Get session by ID
    pub async fn get_session(&self, session_id: uuid::Uuid) -> Result<Session, SessionError> {
        let sessions = self.sessions.read().await;
        
        sessions
            .get(&session_id)
            .cloned()
            .ok_or(SessionError::NotFound)
            .and_then(|s| {
                if s.is_valid() {
                    Ok(s)
                } else {
                    Err(SessionError::Expired)
                }
            })
    }

    /// Get session by token
    pub async fn get_session_by_token(&self, token: &str) -> Result<Session, SessionError> {
        let sessions = self.sessions.read().await;
        
        sessions
            .values()
            .find(|s| s.token == token)
            .cloned()
            .ok_or(SessionError::NotFound)
            .and_then(|s| {
                if s.is_valid() {
                    Ok(s)
                } else {
                    Err(SessionError::Expired)
                }
            })
    }

    /// Invalidate session
    pub async fn invalidate_session(&self, session_id: uuid::Uuid) -> Result<(), SessionError> {
        let mut sessions = self.sessions.write().await;
        
        if let Some(session) = sessions.get_mut(&session_id) {
            session.invalidate();
            info!("Invalidated session {}", session_id);
            Ok(())
        } else {
            Err(SessionError::NotFound)
        }
    }

    /// Invalidate all sessions for user
    pub async fn invalidate_user_sessions(&self, user_id: uuid::Uuid) {
        let mut sessions = self.sessions.write().await;
        
        for session in sessions.values_mut() {
            if session.user_id == user_id {
                session.invalidate();
            }
        }
        
        info!("Invalidated all sessions for user {}", user_id);
    }

    /// Clean up expired sessions
    pub async fn cleanup_expired(&self) -> usize {
        let now = chrono::Utc::now();
        let mut sessions = self.sessions.write().await;
        
        let before = sessions.len();
        sessions.retain(|_, s| s.expires_at > now);
        let after = sessions.len();
        
        debug!("Cleaned up {} expired sessions", before - after);
        before - after
    }

    /// Set session timeout
    pub fn set_timeout(&mut self, secs: i64) {
        self.session_timeout_secs = secs;
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}
