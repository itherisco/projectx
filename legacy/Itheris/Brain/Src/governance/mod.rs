//! Governance Module
//!
//! This module contains the LEP (Law Enforcement Point) decision gate components:
//! - Constitution validation and rule engine
//! - Intent validation and sanitization
//! - LEP Controller - the main decision gate
//!
//! ## Decision Chain
//! 1. Intent validation (input validation)
//! 2. Constitution validation (rule checking)
//! 3. Authorization check (permission verification)
//! 4. Kernel approval (final sovereign approval)
//! 5. Execution (action performed)

pub mod constitution;
pub mod intent_validator;
pub mod lep_controller;

// Re-exports for convenience
pub use constitution::{
    Constitution, ConstitutionDecision, ConstitutionError, ConstitutionResult,
    ConstitutionalAmendment, ConstitutionalRule, EmergencyLevel, ResourceLimits,
    RuleSeverity, RuleType, TemporalConstraints,
};

pub use intent_validator::{
    FieldType, FieldValidator, IntentAction, IntentAuditEntry, IntentSchema,
    IntentValidationError, IntentValidationResult, IntentValidator, RiskLevel,
    ValidatedIntent, IntentPriority,
};

pub use lep_controller::{
    ExecutionRequest, ExecutionResult, LEPDecision, LEPDecisionResult,
    LEPError, LEPResult, LEPStage, LEPController, OverrideRequest, OverrideSignature,
};
