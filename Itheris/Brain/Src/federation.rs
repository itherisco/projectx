//! Multi-Agent Federation - network layer for agent communication

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use chrono::Local;

/// An agent in the federation
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Agent {
    pub id: String,
    pub role: String,
    pub status: String,
    pub last_heartbeat: String,
    pub capabilities: Vec<String>,
    pub reputation: f32,
}

/// A message between agents
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub from: String,
    pub to: String,
    pub intent: String,
    pub payload: Value,
    pub priority: String,
    pub timestamp: String,
    pub signature: String,
}

/// The federation - manages multi-agent network
pub struct Federation {
    pub agents: HashMap<String, Agent>,
    pub message_queue: Vec<Message>,
    pub routing_table: HashMap<String, Vec<String>>,
    pub consensus_threshold: f32,
}

impl Federation {
    pub fn new() -> Self {
        Federation {
            agents: HashMap::new(),
            message_queue: Vec::new(),
            routing_table: HashMap::new(),
            consensus_threshold: 0.67, // 2/3 majority
        }
    }

    /// Register an agent to the federation
    pub fn register_agent(&mut self, agent: Agent) {
        self.agents.insert(agent.id.clone(), agent.clone());
        self.routing_table.insert(agent.id.clone(), Vec::new());
        println!(
            "[FEDERATION] ✓ Agent registered: {} (role: {})",
            agent.id, agent.role
        );
    }

    /// Establish connection between agents
    pub fn connect_agents(&mut self, agent_a: &str, agent_b: &str) -> Result<(), String> {
        if !self.agents.contains_key(agent_a) || !self.agents.contains_key(agent_b) {
            return Err("One or both agents not found".to_string());
        }

        self.routing_table
            .get_mut(agent_a)
            .unwrap()
            .push(agent_b.to_string());
        self.routing_table
            .get_mut(agent_b)
            .unwrap()
            .push(agent_a.to_string());

        println!("[FEDERATION] ✓ Connected: {} <-> {}", agent_a, agent_b);
        Ok(())
    }

    /// Queue a message
    pub fn send_message(&mut self, msg: Message) -> Result<(), String> {
        if !self.agents.contains_key(&msg.to) {
            return Err(format!("Recipient not found: {}", msg.to));
        }

        self.message_queue.push(msg.clone());
        println!("[FEDERATION] ✓ Message queued: {} → {}", msg.from, msg.to);
        Ok(())
    }

    /// Request consensus
    pub fn request_consensus(&self, proposal: &str) -> Result<bool, String> {
        let total = self.agents.len() as f32;
        let required = (total * self.consensus_threshold).ceil() as usize;

        println!(
            "[FEDERATION] ✓ Consensus requested: {}/{} needed",
            required,
            self.agents.len()
        );

        // Simulate consensus voting (in real system, would query agents)
        let approvals = (total * 0.8) as usize;
        Ok(approvals >= required)
    }

    /// Heartbeat - mark agent as alive
    pub fn heartbeat(&mut self, agent_id: &str) -> Result<(), String> {
        if let Some(agent) = self.agents.get_mut(agent_id) {
            agent.last_heartbeat = Local::now().to_rfc3339();
            agent.status = "ONLINE".to_string();
            Ok(())
        } else {
            Err(format!("Agent not found: {}", agent_id))
        }
    }

    /// Detect offline agents
    pub fn detect_failures(&mut self) -> Vec<String> {
        let now = Local::now();
        let mut dead_agents = vec![];

        for (id, agent) in self.agents.iter_mut() {
            if let Ok(last) = chrono::DateTime::parse_from_rfc3339(&agent.last_heartbeat) {
                let duration = now.signed_duration_since(last);
                if duration.num_seconds() > 30 {
                    agent.status = "OFFLINE".to_string();
                    dead_agents.push(id.clone());
                }
            }
        }

        if !dead_agents.is_empty() {
            println!("[FEDERATION] ⚠️  Detected {} offline agents", dead_agents.len());
        }

        dead_agents
    }

    pub fn get_agents(&self) -> &HashMap<String, Agent> {
        &self.agents
    }

    pub fn get_routing_table(&self) -> &HashMap<String, Vec<String>> {
        &self.routing_table
    }

    pub fn message_count(&self) -> usize {
        self.message_queue.len()
    }
}

impl Default for Federation {
    fn default() -> Self {
        Self::new()
    }
}