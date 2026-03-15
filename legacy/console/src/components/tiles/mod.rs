//! ITHERIS Console - Modular Tile Components
//! 
//! Reusable tile components for the bento grid layout.

use leptos::*;

/// Base tile component
#[component]
pub fn Tile(
    #[prop] title: String,
    #[prop] icon: String,
    #[prop] children: Children,
) -> impl IntoView {
    view! {
        <div class="tile">
            <div class="tile-header">
                <span class="tile-icon">{icon}</span>
                <h3 class="tile-title">{title}</h3>
            </div>
            <div class="tile-content">
                {children()}
            </div>
        </div>
    }
}

/// Energy tile component
#[component]
pub fn EnergyTile(
    #[prop] level: f64,
) -> impl IntoView {
    let percentage = format!("{:.1}%", level * 100.0);
    let color = if level > 0.5 {
        "#22c55e"
    } else if level > 0.2 {
        "#f59e0b"
    } else {
        "#ef4444"
    };
    
    view! {
        <div class="energy-tile">
            <div class="energy-value" style=format!("color: {}", color)>
                {percentage}
            </div>
            <div class="energy-bar">
                <div 
                    class="energy-fill" 
                    style=format!("width: {}%; background: {}", level * 100.0, color)
                ></div>
            </div>
        </div>
    }
}

/// Status tile component
#[component]
pub fn StatusTile(
    #[prop] label: String,
    #[prop] value: String,
    #[prop] is_online: bool,
) -> impl IntoView {
    view! {
        <div class="status-tile">
            <span class="status-label">{label}</span>
            <span class={format!("status-value {}", if is_online { "online" } else { "offline" })}>
                {value}
            </span>
        </div>
    }
}

/// Chart tile component
#[component]
pub fn ChartTile(
    #[prop] title: String,
    #[prop] data: Vec<f64>,
) -> impl IntoView {
    let max = data.iter().cloned().fold(0.0f64, f64::max);
    
    view! {
        <div class="chart-tile">
            <h4 class="chart-title">{title}</h4>
            <div class="chart-container">
                {data.into_iter().enumerate().map(|(i, v)| {
                    let height = if max > 0.0 { (v / max) * 100.0 } else { 0.0 };
                    view! {
                        <div class="chart-bar" style=format!("height: {}%", height)></div>
                    }
                }).collect_view()}
            </div>
        </div>
    }
}
