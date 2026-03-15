//! ITHERIS Console - Root Application Component
//! 
//! Main application component with routing, layout, and theme provider.

use leptos::*;
use leptos_router::*;

use crate::components::bento_grid::BentoGrid;
use crate::pages::dashboard::Dashboard;
use crate::pages::decision_spine::DecisionSpinePage;
use crate::pages::metabolic::MetabolicPage;
use crate::pages::containment::ContainmentPage;
use crate::state::signals::MetabolicSignals;
use crate::state::theme::{Theme, ThemeProvider, CIRCADIAN_THEMES};

/// Route paths
#[derive(Clone, Debug)]
pub struct RoutePaths;

impl RoutePaths {
    pub const DASHBOARD: &'static str = "/";
    pub const DECISION_SPINE: &'static str = "/decisions";
    pub const METABOLIC: &'static str = "/metabolic";
    pub const CONTAINMENT: &'static str = "/containment";
}

/// Navigation item for sidebar
#[derive(Clone)]
pub struct NavItem {
    pub path: &'static str,
    pub label: &'static str,
    pub icon: &'static str,
}

/// Get navigation items
pub fn get_nav_items() -> Vec<NavItem> {
    vec![
        NavItem {
            path: RoutePaths::DASHBOARD,
            label: "Dashboard",
            icon: "◈",
        },
        NavItem {
            path: RoutePaths::DECISION_SPINE,
            label: "Decision Spine",
            icon: "◇",
        },
        NavItem {
            path: RoutePaths::METABOLIC,
            label: "Metabolic",
            icon: "⚡",
        },
        NavItem {
            path: RoutePaths::CONTAINMENT,
            label: "Containment",
            icon: "⬡",
        },
    ]
}

/// Sidebar navigation component
#[component]
pub fn Sidebar(
    #[prop] current_path: String,
) -> impl IntoView {
    let nav_items = get_nav_items();
    
    view! {
        <aside class="sidebar">
            <div class="sidebar-header">
                <span class="logo-icon">"◈"</span>
                <span class="logo-text">"ITHERIS"</span>
            </div>
            
            <nav class="sidebar-nav">
                {nav_items.into_iter().map(|item| {
                    let is_active = current_path == item.path.to_string();
                    view! {
                        <A 
                            href=item.path 
                            class=format!("nav-item {}", if is_active { "active" } else { "" })
                        >
                            <span class="nav-icon">{item.icon}</span>
                            <span class="nav-label">{item.label}</span>
                        </A>
                    }
                }).collect_view()}
            </nav>
            
            <div class="sidebar-footer">
                <span class="version">"v0.1.0"</span>
            </div>
        </aside>
    }
}

/// Main layout component
#[component]
pub fn MainLayout(
    #[prop] children: Children,
) -> impl IntoView {
    let location = use_location();
    let current_path = || location move().pathname;
    
    // Initialize theme
    let theme = Theme::default();
    
    view! {
        <ThemeProvider theme=theme>
            <div class="app-layout">
                <Sidebar current_path=current_path() />
                <main class="main-content">
                    {children()}
                </main>
            </div>
        </ThemeProvider>
    }
}

/// App routes configuration
#[derive(Clone, Routable)]
pub enum AppRoutes {
    #[at(RoutePaths::DASHBOARD)]
    Dashboard,
    
    #[at(RoutePaths::DECISION_SPINE)]
    DecisionSpine,
    
    #[at(RoutePaths::METABOLIC)]
    Metabolic,
    
    #[at(RoutePaths::CONTAINMENT)]
    Containment,
    
    #[not_found]
    #[at("/404")]
    NotFound,
}

/// Main App component with routing
#[component]
pub fn App() -> impl IntoView {
    // Initialize metabolic signals
    let metabolic_signals = MetabolicSignals::new();
    
    // Get CSS styles
    let css = crate::components::bento_grid::get_combined_css();
    
    view! {
        <Router>
            <Routes>
                <Route path="/" view=MainLayout>
                    <Route path="" view=DashboardPage />
                    <Route path="/decisions" view=DecisionSpinePage />
                    <Route path="/metabolic" view=MetabolicPage />
                    <Route path="/containment" view=ContainmentPage />
                </Route>
            </Routes>
        </Router>
    }
}

/// Dashboard page wrapper
#[component]
fn DashboardPage() -> impl IntoView {
    let metabolic_signals = MetabolicSignals::new();
    let css = crate::components::bento_grid::get_combined_css();
    
    view! {
        <div class="page dashboard-page">
            <style>{css}</style>
            <BentoGrid metabolic_signals=metabolic_signals />
        </div>
    }
}

/// Re-export for use in main.rs
pub use crate::lib::App as LeptosApp;
