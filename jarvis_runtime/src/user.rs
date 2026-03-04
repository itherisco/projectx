//! # User - User Management
//!
//! User struct with UUID, preferences, and trust levels.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use chrono::{DateTime, Utc};

/// Trust levels for user access control
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrustLevel {
    Guest,
    Basic,
    Trusted,
    Admin,
}

impl Default for TrustLevel {
    fn default() -> Self {
        TrustLevel::Guest
    }
}

impl TrustLevel {
    pub fn can_execute(&self, capability: &str) -> bool {
        match self {
            TrustLevel::Guest => matches!(capability, "read" | "query"),
            TrustLevel::Basic => matches!(capability, "read" | "query" | "basic"),
            TrustLevel::Trusted => true,
            TrustLevel::Admin => true,
        }
    }

    pub fn level(&self) -> u8 {
        match self {
            TrustLevel::Guest => 0,
            TrustLevel::Basic => 1,
            TrustLevel::Trusted => 2,
            TrustLevel::Admin => 3,
        }
    }
}

/// User preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPreferences {
    /// Preferred language
    pub language: String,
    /// Theme preference
    pub theme: String,
    /// Notification settings
    pub notifications: NotificationSettings,
    /// Privacy settings
    pub privacy: PrivacySettings,
    /// Custom preferences
    pub custom: HashMap<String, serde_json::Value>,
}

impl Default for UserPreferences {
    fn default() -> Self {
        Self {
            language: "en".to_string(),
            theme: "system".to_string(),
            notifications: NotificationSettings::default(),
            privacy: PrivacySettings::default(),
            custom: HashMap::new(),
        }
    }
}

/// Notification settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationSettings {
    pub enabled: bool,
    pub sound: bool,
    pub desktop: bool,
    pub email: bool,
}

impl Default for NotificationSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            sound: true,
            desktop: true,
            email: false,
        }
    }
}

/// Privacy settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivacySettings {
    pub share_usage_data: bool,
    pub allow_proactive: bool,
    pub store_conversations: bool,
    pub retention_days: u32,
}

impl Default for PrivacySettings {
    fn default() -> Self {
        Self {
            share_usage_data: false,
            allow_proactive: true,
            store_conversations: true,
            retention_days: 30,
        }
    }
}

/// User struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    /// Unique user ID
    pub id: uuid::Uuid,
    /// Username
    pub username: String,
    /// Email (optional, for auth)
    pub email: Option<String>,
    /// Hashed password
    pub password_hash: Option<String>,
    /// Trust level
    pub trust_level: TrustLevel,
    /// User preferences
    pub preferences: UserPreferences,
    /// Memory namespace (isolated per user)
    pub memory_namespace: String,
    /// When user was created
    pub created_at: DateTime<Utc>,
    /// Last active timestamp
    pub last_active: DateTime<Utc>,
    /// Whether user is active
    pub is_active: bool,
}

impl User {
    /// Create a new user
    pub fn new(username: String) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4(),
            username,
            email: None,
            password_hash: None,
            trust_level: TrustLevel::Basic,
            preferences: UserPreferences::default(),
            memory_namespace: format!("user_{}", uuid::Uuid::new_v4()),
            created_at: now,
            last_active: now,
            is_active: true,
        }
    }

    /// Create admin user
    pub fn new_admin(username: String) -> Self {
        Self {
            trust_level: TrustLevel::Admin,
            ..Self::new(username)
        }
    }

    /// Update last active timestamp
    pub fn update_activity(&mut self) {
        self.last_active = Utc::now();
    }

    /// Set password hash
    pub fn set_password(&mut self, hash: String) {
        self.password_hash = Some(hash);
    }

    /// Check if user has password set
    pub fn has_password(&self) -> bool {
        self.password_hash.is_some()
    }

    /// Verify trust level
    pub fn can_trust(&self, required: TrustLevel) -> bool {
        self.trust_level.level() >= required.level()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_creation() {
        let user = User::new("testuser".to_string());
        assert_eq!(user.username, "testuser");
        assert_eq!(user.trust_level, TrustLevel::Basic);
        assert!(user.is_active);
    }

    #[test]
    fn test_trust_levels() {
        assert!(!TrustLevel::Guest.can_execute("write"));
        assert!(TrustLevel::Trusted.can_execute("write"));
    }
}
