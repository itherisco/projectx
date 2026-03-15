//! ITHERIS Console State Management
//! 
//! Reactive state management using Leptos signals.

pub mod signals;
pub mod theme;

pub use signals::{CognitiveMode, MetabolicSignals, MetabolicState, ENERGY_MAX, ENERGY_CRITICAL, ENERGY_DEATH, ENERGY_RECOVERY};
pub use theme::{Theme, ThemeProvider, CircadianTheme, CIRCADIAN_THEMES};
