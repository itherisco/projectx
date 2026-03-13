//! ITHERIS Console Pages
//! 
//! Page components for the management console.

pub mod dashboard;
pub mod decision_spine;
pub mod metabolic;
pub mod containment;

pub use dashboard::Dashboard;
pub use decision_spine::DecisionSpinePage;
pub use metabolic::MetabolicPage;
pub use containment::ContainmentPage;
