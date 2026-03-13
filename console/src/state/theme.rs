//! ITHERIS Theme State Management
//! 
//! Theme provider and circadian adaptive theming for the ITHERIS console.

use leptos::*;
use serde::{Deserialize, Serialize};

/// Circadian theme presets
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CircadianTheme {
    /// Morning theme (6 AM - 12 PM)
    Morning,
    /// Afternoon theme (12 PM - 6 PM)
    Afternoon,
    /// Evening theme (6 PM - 10 PM)
    Evening,
    /// Night theme (10 PM - 6 AM)
    Night,
}

impl CircadianTheme {
    /// Get theme name
    pub fn name(&self) -> &'static str {
        match self {
            CircadianTheme::Morning => "Morning",
            CircadianTheme::Afternoon => "Afternoon",
            CircadianTheme::Evening => "Evening",
            CircadianTheme::Night => "Night",
        }
    }
    
    /// Get CSS variables for the theme
    pub fn get_css_vars(&self) -> Vec<(&'static str, &'static str)> {
        match self {
            CircadianTheme::Morning => vec![
                ("--bg-primary", "#fafafa"),
                ("--bg-secondary", "#f5f5f4"),
                ("--bg-tertiary", "#e7e5e4"),
                ("--text-primary", "#1c1917"),
                ("--text-secondary", "#57534e"),
                ("--accent-primary", "#f59e0b"),
                ("--accent-secondary", "#fbbf24"),
                ("--border-color", "#d6d3d1"),
            ],
            CircadianTheme::Afternoon => vec![
                ("--bg-primary", "#ffffff"),
                ("--bg-secondary", "#f8fafc"),
                ("--bg-tertiary", "#f1f5f9"),
                ("--text-primary", "#0f172a"),
                ("--text-secondary", "#475569"),
                ("--accent-primary", "#3b82f6"),
                ("--accent-secondary", "#60a5fa"),
                ("--border-color", "#e2e8f0"),
            ],
            CircadianTheme::Evening => vec![
                ("--bg-primary", "#1e1e2e"),
                ("--bg-secondary", "#2a2a3e"),
                ("--bg-tertiary", "#363650"),
                ("--text-primary", "#e4e4e7"),
                ("--text-secondary", "#a1a1aa"),
                ("--accent-primary", "#8b5cf6"),
                ("--accent-secondary", "#a78bfa"),
                ("--border-color", "#4a4a6a"),
            ],
            CircadianTheme::Night => vec![
                ("--bg-primary", "#0a0a0f"),
                ("--bg-secondary", "#12121a"),
                ("--bg-tertiary", "#1a1a24"),
                ("--text-primary", "#e4e4e7"),
                ("--text-secondary", "#71717a"),
                ("--accent-primary", "#6366f1"),
                ("--accent-secondary", "#818cf8"),
                ("--border-color", "#27272a"),
            ],
        }
    }
}

/// Current theme with manual override capability
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Theme {
    /// Current active circadian theme
    pub circadian: CircadianTheme,
    /// Manual override - if set, use this instead of auto
    pub override_theme: Option<CircadianTheme>,
    /// Enable auto-circadian switching
    pub auto_circadian: bool,
}

impl Default for Theme {
    fn default() -> Self {
        Self {
            circadian: CircadianTheme::Afternoon,
            override_theme: None,
            auto_circadian: true,
        }
    }
}

impl Theme {
    /// Create a new theme with default settings
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Get the current effective theme
    pub fn effective_theme(&self) -> CircadianTheme {
        self.override_theme.unwrap_or(self.circadian)
    }
    
    /// Generate CSS variables string
    pub fn generate_css(&self) -> String {
        let theme = self.effective_theme();
        theme.get_css_vars()
            .iter()
            .map(|(name, value)| format!("{}: {};", name, value))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

/// Theme context provider component
#[component]
pub fn ThemeProvider(
    theme: Theme,
    #[prop] children: Children,
) -> impl IntoView {
    let css_vars = theme.generate_css();
    
    view! {
        <div class="theme-provider" style={css_vars}>
            {children()}
        </div>
    }
}

/// Available circadian themes
pub const CIRCADIAN_THEMES: &[CircadianTheme] = &[
    CircadianTheme::Morning,
    CircadianTheme::Afternoon,
    CircadianTheme::Evening,
    CircadianTheme::Night,
];
