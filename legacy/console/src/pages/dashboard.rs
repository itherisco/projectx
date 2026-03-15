//! ITHERIS Dashboard Page
//! 
//! Main dashboard page with bento grid layout showing system overview.

use leptos::*;
use crate::components::bento_grid::BentoGrid;
use crate::state::signals::MetabolicSignals;

/// Dashboard page component
#[component]
pub fn Dashboard() -> impl IntoView {
    let metabolic_signals = MetabolicSignals::new();
    
    // Get CSS styles
    let css = crate::components::bento_grid::get_combined_css();
    
    view! {
        <div class="page dashboard-page">
            <style>{css}</style>
            <div class="page-header">
                <h1>"System Dashboard"</h1>
                <span class="status-badge online">"OPERATIONAL"</span>
            </div>
            
            <BentoGrid metabolic_signals=metabolic_signals />
        </div>
    }
}
