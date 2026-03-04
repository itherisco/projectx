//! LLM Advisor - provides suggestions without authority

use serde_json::{json, Value};

/// An advice from the LLM
#[derive(Clone, Debug)]
pub struct Advice {
    pub advisor: String,
    pub query: String,
    pub suggestion: String,
    pub confidence: f32,
    pub reasoning: String,
    pub disclaimer: String,
}

/// LLM Advisor - advisory only, no authority
pub struct LLMAdvisor {
    pub name: String,
    pub model: String,
    pub max_tokens: usize,
    pub temperature: f32,
    pub is_enabled: bool,
}

impl LLMAdvisor {
    pub fn new(name: &str, model: &str) -> Self {
        LLMAdvisor {
            name: name.to_string(),
            model: model.to_string(),
            max_tokens: 500,
            temperature: 0.3, // Low randomness
            is_enabled: true,
        }
    }

    /// Request advice (deterministic for now, connect to OpenAI in production)
    pub fn request_advice(&self, query: &str, _context: &Value) -> Result<Advice, String> {
        if !self.is_enabled {
            return Err("LLM advisor is disabled".to_string());
        }

        // In production: call OpenAI/Claude API
        let advice_text = match query {
            q if q.contains("threat") => {
                "Recommend immediate escalation. High-risk scenarios require multi-agent consensus."
            }
            q if q.contains("resource") => {
                "Suggest gradual optimization with monitoring. Avoid aggressive changes in production."
            }
            q if q.contains("cache") => {
                "Current configuration appears stable. Historical data shows risk outweighs potential gains."
            }
            _ => "Unable to generate meaningful advice for this query.",
        };

        let advice = Advice {
            advisor: self.name.clone(),
            query: query.to_string(),
            suggestion: advice_text.to_string(),
            confidence: 0.72,
            reasoning: "Analysis based on pattern matching".to_string(),
            disclaimer: "⚠️  ADVISORY ONLY. Final authority: CRITIC and KERNEL.".to_string(),
        };

        println!("[LLM_ADVISOR] ✓ Advice generated (confidence: {})", advice.confidence);
        Ok(advice)
    }

    /// Validate advice against ground truth
    pub fn validate_advice(&self, advice: &Advice, ground_truth: &Value) -> Result<bool, String> {
        let ground_truth_str = ground_truth.to_string().to_lowercase();
        let advice_str = advice.suggestion.to_lowercase();

        let contradiction = advice_str.contains("stable") && ground_truth_str.contains("high_load");

        if contradiction {
            println!("[LLM_ADVISOR] ✗ HALLUCINATION DETECTED");
            return Ok(false);
        }

        println!("[LLM_ADVISOR] ✓ Advice validated");
        Ok(true)
    }

    pub fn disable(&mut self) {
        self.is_enabled = false;
        println!("[LLM_ADVISOR] ⚠️  Advisor disabled");
    }

    pub fn enable(&mut self) {
        self.is_enabled = true;
        println!("[LLM_ADVISOR] ✓ Advisor enabled");
    }
}