//! Internal Debate System - Strategist vs Critic with confidence tracking

use crate::crypto::SignedThought;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use chrono::Local;

/// A position taken by a cognitive identity
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Position {
    pub identity: String,
    pub claim: String,
    pub evidence: Value,
    pub confidence: f32,
    pub thought_hash: String,
}

/// A challenge to a position
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Challenge {
    pub challenger: String,
    pub target_hash: String,
    pub objection: String,
    pub counter_evidence: Option<Value>,
    pub severity: f32,
}

/// The outcome of a debate
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DebateOutcome {
    pub proposition: Position,
    pub challenges: Vec<Challenge>,
    pub verdict: String,
    pub confidence_delta: f32,
    pub timestamp: String,
}

/// The debate engine - orchestrates internal debate between agents
pub struct DebateEngine {
    pub positions: Vec<Position>,
    pub challenges: Vec<Challenge>,
    pub outcomes: Vec<DebateOutcome>,
}

impl DebateEngine {
    pub fn new() -> Self {
        DebateEngine {
            positions: Vec::new(),
            challenges: Vec::new(),
            outcomes: Vec::new(),
        }
    }

    /// STRATEGIST proposes a position (signed thought)
    pub fn propose(&mut self, thought: &SignedThought) -> Position {
        let position = Position {
            identity: thought.identity.clone(),
            claim: thought.intent.clone(),
            evidence: thought.evidence.clone().unwrap_or(json!({})),
            confidence: 0.75,
            thought_hash: thought.message_hash.clone(),
        };

        self.positions.push(position.clone());
        println!(
            "[DEBATE] ✓ Position proposed by {}: {}",
            thought.identity, thought.intent
        );

        position
    }

    /// CRITIC challenges a position
    pub fn challenge(
        &mut self,
        challenger: &str,
        target_hash: &str,
        objection: String,
        counter_evidence: Option<Value>,
    ) -> Challenge {
        let severity = counter_evidence.as_ref().map(|_| 0.8).unwrap_or(0.5);

        let challenge = Challenge {
            challenger: challenger.to_string(),
            target_hash: target_hash.to_string(),
            objection,
            counter_evidence,
            severity,
        };

        self.challenges.push(challenge.clone());
        println!(
            "[DEBATE] ⚠️  Challenge from {}: severity={}",
            challenger, severity
        );

        challenge
    }

    /// Resolve debate - compute final confidence after challenges
    pub fn resolve(&mut self, proposition_hash: &str) -> DebateOutcome {
        let proposition = self
            .positions
            .iter()
            .find(|p| p.thought_hash == proposition_hash)
            .cloned()
            .expect("Proposition not found");

        let relevant_challenges: Vec<Challenge> = self
            .challenges
            .iter()
            .filter(|c| c.target_hash == proposition_hash)
            .cloned()
            .collect();

        // Calculate confidence delta based on challenges
        let mut confidence_delta = 0.0f32;
        for challenge in &relevant_challenges {
            if challenge.counter_evidence.is_some() {
                confidence_delta -= challenge.severity;
            } else {
                confidence_delta -= challenge.severity * 0.5; // Weaker without evidence
            }
        }

        let final_confidence =
            (proposition.confidence + confidence_delta).max(0.0).min(1.0);

        let verdict = if final_confidence > 0.75 {
            "CONSENSUS_REACHED_STRONG".to_string()
        } else if final_confidence > 0.6 {
            "CONSENSUS_REACHED".to_string()
        } else if final_confidence > 0.5 {
            "UNCERTAIN_PROCEED_WITH_CAUTION".to_string()
        } else {
            "REJECTED_INSUFFICIENT_CONFIDENCE".to_string()
        };

        let outcome = DebateOutcome {
            proposition,
            challenges: relevant_challenges,
            verdict,
            confidence_delta,
            timestamp: Local::now().to_rfc3339(),
        };

        self.outcomes.push(outcome.clone());

        println!(
            "[DEBATE] ✓ Resolved: {} (final confidence: {})",
            outcome.verdict,
            final_confidence
        );

        outcome
    }

    pub fn get_outcomes(&self) -> &Vec<DebateOutcome> {
        &self.outcomes
    }

    pub fn debate_count(&self) -> usize {
        self.outcomes.len()
    }
}

impl Default for DebateEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_debate_with_challenges() {
        let mut debate = DebateEngine::new();
        let position = Position {
            identity: "TEST".to_string(),
            claim: "ACTION_A".to_string(),
            evidence: json!({"reason": "test"}),
            confidence: 0.8,
            thought_hash: "hash123".to_string(),
        };

        debate.positions.push(position.clone());
        debate.challenge("CRITIC", "hash123", "Not enough evidence".to_string(), 
                        Some(json!({"counter": "evidence"})));

        let outcome = debate.resolve("hash123");
        assert!(outcome.confidence_delta < 0.0);
    }
}