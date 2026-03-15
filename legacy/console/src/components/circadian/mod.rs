//! ITHERIS Console - Circadian Adaptive Theming
//! 
//! Circadian rhythm-based theme switching for the ITHERIS console.

use leptos::*;
use crate::state::theme::{Theme, CircadianTheme, CIRCADIAN_THEMES};

/// Get the current hour-based circadian theme
pub fn get_circadian_theme() -> CircadianTheme {
    use chrono::Timelike;
    let hour = chrono::Utc::now().hour();
    
    match hour {
        6..=11 => CircadianTheme::Morning,
        12..=17 => CircadianTheme::Afternoon,
        18..=21 => CircadianTheme::Evening,
        _ => CircadianTheme::Night,
    }
}

/// Circadian theme switcher component
#[component]
pub fn CircadianSwitcher(
    #[prop] current_theme: CircadianTheme,
    #[prop] on_theme_change: Callback<CircadianTheme>,
) -> impl IntoView {
    view! {
        <div class="circadian-switcher">
            <span class="switcher-label">"Theme:"</span>
            <div class="theme-options">
                {CIRCADIAN_THEMES.iter().map(|theme| {
                    let is_active = *theme == current_theme;
                    view! {
                        <button 
                            class=format!("theme-btn {}", if is_active { "active" } else { "" })
                            on_click=move |_| {
                                on_theme_change(*theme);
                            }
                        >
                            {theme.name()}
                        </button>
                    }
                }).collect_view()}
            </div>
        </div>
    }
}

/// Theme preview component
#[component]
pub fn ThemePreview(
    #[prop] theme: CircadianTheme,
) -> impl IntoView {
    let colors = theme.get_css_vars();
    let bg = colors.iter().find(|(n, _)| *n == "--bg-primary").map(|(_, v)| *v).unwrap_or("#000");
    let text = colors.iter().find(|(n, _)| *n == "--text-primary").map(|(_, v)| *v).unwrap_or("#fff");
    let accent = colors.iter().find(|(n, _)| *n == "--accent-primary").map(|(_, v)| *v).unwrap_or("#6366f1");
    
    view! {
        <div class="theme-preview" style=format!("background: {}; color: {}; border-color: {}", bg, text, accent)>
            <span class="preview-icon">"◈"</span>
            <span class="preview-name">{theme.name()}</span>
        </div>
    }
}

/// Auto-circadian indicator
#[component]
pub fn CircadianIndicator() -> impl IntoView {
    let current = get_circadian_theme();
    
    view! {
        <div class="circadian-indicator">
            <span class="indicator-icon">"◐"</span>
            <span class="indicator-label">"Current: "</span>
            <ThemePreview theme=current />
        </div>
    }
}
