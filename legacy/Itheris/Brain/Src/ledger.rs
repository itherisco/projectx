//! Immutable Ledger - blockchain-style audit trail

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use chrono::Local;
use std::collections::VecDeque;

/// A block in the ledger
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LedgerBlock {
    pub index: u64,
    pub timestamp: String,
    pub entries: Vec<LedgerEntry>,
    pub previous_hash: String,
    pub block_hash: String,
    pub nonce: u64,
}

/// An entry in a block
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LedgerEntry {
    pub entry_type: String,
    pub identity: String,
    pub action: String,
    pub details: Value,
    pub signature: String,
    pub timestamp: String,
}

/// Immutable ledger with hash chain
pub struct ImmutableLedger {
    blocks: VecDeque<LedgerBlock>,
    pending_entries: Vec<LedgerEntry>,
    block_size: usize,
}

impl ImmutableLedger {
    pub fn new(block_size: usize) -> Self {
        let mut ledger = ImmutableLedger {
            blocks: VecDeque::new(),
            pending_entries: Vec::new(),
            block_size,
        };

        ledger.create_genesis_block();
        ledger
    }

    fn create_genesis_block(&mut self) {
        let block = LedgerBlock {
            index: 0,
            timestamp: Local::now().to_rfc3339(),
            entries: vec![],
            previous_hash: "GENESIS".to_string(),
            block_hash: Self::compute_hash("GENESIS", 0, &[]),
            nonce: 0,
        };

        self.blocks.push_back(block);
        println!("[LEDGER] ✓ Genesis block created");
    }

    fn compute_hash(prev_hash: &str, index: u64, entries: &[LedgerEntry]) -> String {
        let data = json!({
            "index": index,
            "previous_hash": prev_hash,
            "entries": entries,
            "timestamp": Local::now().to_rfc3339()
        })
        .to_string();

        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        hex::encode(hasher.finalize())
    }

    /// Record an entry
    pub fn record_entry(
        &mut self,
        entry_type: &str,
        identity: &str,
        action: &str,
        details: Value,
        signature: String,
    ) {
        let entry = LedgerEntry {
            entry_type: entry_type.to_string(),
            identity: identity.to_string(),
            action: action.to_string(),
            details,
            signature,
            timestamp: Local::now().to_rfc3339(),
        };

        self.pending_entries.push(entry);

        if self.pending_entries.len() >= self.block_size {
            self.seal_block();
        }
    }

    /// Seal pending entries into a block
    pub fn seal_block(&mut self) {
        if self.pending_entries.is_empty() {
            return;
        }

        let last_block = self.blocks.back().unwrap();
        let index = last_block.index + 1;
        let previous_hash = last_block.block_hash.clone();

        let entries = self.pending_entries.drain(..).collect::<Vec<_>>();
        let block_hash = Self::compute_hash(&previous_hash, index, &entries);

        let block = LedgerBlock {
            index,
            timestamp: Local::now().to_rfc3339(),
            entries,
            previous_hash,
            block_hash,
            nonce: 0,
        };

        self.blocks.push_back(block.clone());
        println!("[LEDGER] ✓ Block #{} sealed (hash: {}...)", index, &block.block_hash[0..16]);
    }

    /// Verify ledger integrity
    pub fn verify_integrity(&self) -> bool {
        for i in 1..self.blocks.len() {
            let prev_block = &self.blocks[i - 1];
            let curr_block = &self.blocks[i];

            if curr_block.previous_hash != prev_block.block_hash {
                println!("[LEDGER] ✗ Chain break at block {}", i);
                return false;
            }

            let computed_hash = Self::compute_hash(
                &curr_block.previous_hash,
                curr_block.index,
                &curr_block.entries,
            );

            if computed_hash != curr_block.block_hash {
                println!("[LEDGER] ✗ Hash mismatch at block {}", i);
                return false;
            }
        }

        println!("[LEDGER] ✓ Integrity verified ({} blocks)", self.blocks.len());
        true
    }

    pub fn export(&self) -> Value {
        json!({
            "blocks": self.blocks.len(),
            "pending_entries": self.pending_entries.len(),
            "total_entries": self.blocks.iter().map(|b| b.entries.len()).sum::<usize>(),
            "hash_chain_valid": self.verify_integrity()
        })
    }

    pub fn get_blocks(&self) -> &VecDeque<LedgerBlock> {
        &self.blocks
    }

    pub fn block_count(&self) -> usize {
        self.blocks.len()
    }
}

impl Default for ImmutableLedger {
    fn default() -> Self {
        Self::new(10)
    }
}

use hex;