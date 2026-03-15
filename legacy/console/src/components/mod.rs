//! ITHERIS Console Components
//! 
//! UI components for the management console.

pub mod bento_grid;
pub mod metabolic_tile;
pub mod decision_spine_tile;
pub mod oneiric_tile;
pub mod unsealing_tile;
pub mod tiles;
pub mod circadian;

// Re-export for convenience
pub use tiles::{Tile, EnergyTile, StatusTile, ChartTile};
pub use circadian::{CircadianSwitcher, ThemePreview, CircadianIndicator, get_circadian_theme};
