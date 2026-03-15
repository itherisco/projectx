# ITHERIS Cognitive Brain - Complete Implementation Prompt

## Context

You are helping complete the **ITHERIS** project - a sovereign cognitive AI system combining Julia (cognition) + Rust (security kernel) into a JARVIS-like personal assistant. The project exists at `github.com/itherisco/projectx` with partial implementation.

**Current Status:**
- ✅ Julia kernel with basic decision logic (70KB)
- ✅ Rust brain stub with IPC framework
- ✅ 55 passing tests
- ⚠️ Security: 12/100 (critical vulnerabilities)
- ⚠️ IPC: Fallback mode (incomplete Rust-Julia integration)
- ⚠️ Overall: 43/100 maturity

**Goal:** Complete ITHERIS to 80/100+ maturity with production-ready components.

---

## Phase 1: Stabilize Core Infrastructure (Priority: CRITICAL)

### Task 1.1: Complete Rust-Julia IPC Integration

**File:** `Itheris/Brain/Src/ipc/ring_buffer.rs`

```rust
// Implement a stable, production-grade ring buffer for Julia-Rust communication
// Requirements:
// - Lock-free single-producer-single-consumer ring buffer
// - Message versioning and backward compatibility
// - Automatic reconnection on disconnection
// - Heartbeat mechanism (1 Hz)
// - Performance: 10,000+ messages/second
// - Memory: Fixed allocation, no dynamic growth

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use serde::{Serialize, Deserialize};

#[derive(Serialize, Deserialize)]
pub enum Message {
    Proposal { id: u64, action: String, confidence: f32, features: Vec<f32> },
    Verdict { proposal_id: u64, approved: bool, reward: f32, reason: Option<String> },
    WorldState { timestamp: u64, energy: f32, observations: HashMap<String, f32> },
    Heartbeat { sender: String, timestamp: u64 },
}

pub struct RingBuffer {
    // TODO: Implement lock-free ring buffer
    // Use crossbeam or custom atomic implementation
    // Add versioning, heartbeat, reconnection logic
}

// Implement:
impl RingBuffer {
    pub fn new(capacity: usize) -> Self { todo!() }
    pub fn send(&self, msg: Message) -> Result<(), IpcError> { todo!() }
    pub fn receive(&self) -> Result<Message, IpcError> { todo!() }
    pub fn is_connected(&self) -> bool { todo!() }
    pub fn reconnect(&mut self) -> Result<(), IpcError> { todo!() }
}
```

**File:** `adaptive-kernel/kernel/ipc/IPC.jl`

```julia
# Julia side of IPC - mirror the Rust implementation
# Requirements:
# - Connect to Rust ring buffer via shared memory or TCP
# - Handle disconnections gracefully (enter SAFE_MODE)
# - Async message processing with proper error handling
# - Timeout handling (1 second max wait)

module IPC

using Sockets
using JSON3
using Dates

export send_proposal, receive_verdict, is_brain_connected

mutable struct IPCChannel
    socket::Union{TCPSocket, Nothing}
    last_heartbeat::DateTime
    reconnect_attempts::Int
    max_reconnect_attempts::Int
end

# TODO: Implement robust IPC with:
# - Automatic reconnection (exponential backoff)
# - Heartbeat monitoring
# - Message queue for failed sends
# - Graceful degradation to SAFE_MODE

function send_proposal(channel::IPCChannel, proposal::Proposal)
    # TODO: Implement with timeout and error handling
end

function receive_verdict(channel::IPCChannel)::Union{Verdict, Nothing}
    # TODO: Implement with timeout
end

end # module
```

**Success Criteria:**
- [ ] 24+ hour continuous operation without disconnection
- [ ] 10,000+ messages/second throughput
- [ ] Automatic reconnection within 5 seconds
- [ ] Zero data loss during reconnection
- [ ] Exit fallback mode permanently

---

### Task 1.2: Cryptographic Security Layer

**File:** `adaptive-kernel/kernel/security/Crypto.jl`

```julia
# Implement production-grade cryptographic security
# Requirements:
# - HMAC-SHA256 signed action tokens
# - Constant-time signature verification
# - Key rotation support
# - Audit logging of all signature verifications

using SHA
using Random

struct ActionToken
    action::Action
    timestamp::DateTime
    nonce::Vector{UInt8}
    signature::Vector{UInt8}
end

# TODO: Implement:
function sign_action(action::Action, secret_key::Vector{UInt8})::ActionToken
    # Generate nonce
    # Create message = serialize(action) || timestamp || nonce
    # signature = HMAC-SHA256(secret_key, message)
    # Return ActionToken
end

function verify_token(token::ActionToken, secret_key::Vector{UInt8})::Bool
    # Recompute signature
    # Use constant_time_compare (prevent timing attacks)
    # Log verification result to audit trail
    # Return true/false
end

function constant_time_compare(a::Vector{UInt8}, b::Vector{UInt8})::Bool
    # TODO: Implement constant-time comparison to prevent timing attacks
    # XOR all bytes and check if result is zero
end

function rotate_keys!(kernel::Kernel)
    # TODO: Implement key rotation
    # Generate new key
    # Re-sign pending actions
    # Archive old key
end
```

**Success Criteria:**
- [ ] All actions cryptographically signed
- [ ] Zero timing-attack vulnerabilities
- [ ] Key rotation every 24 hours
- [ ] Audit log of all verifications
- [ ] Security score: 60/100+

---

### Task 1.3: Input Sanitization & Validation

**File:** `adaptive-kernel/cognition/security/InputSanitizer.jl`

```julia
# Comprehensive input sanitization for all user inputs and LLM outputs
# Requirements:
# - Block all shell injection patterns
# - Validate file paths against allowlist
# - Sanitize SQL-like queries
# - Detect prompt injection attempts
# - Rate limiting on suspicious patterns

module InputSanitizer

export sanitize_input, sanitize_shell_command, sanitize_path, detect_injection

# Shell injection patterns (block these)
const SHELL_FORBIDDEN = [";", "|", "&", "\$", "`", "\\n", "&&", "||", ">", "<", "*", "?"]

# Prompt injection patterns (flag these)
const INJECTION_PATTERNS = [
    r"ignore (previous|above) instructions"i,
    r"you are now"i,
    r"system prompt"i,
    r"developer mode"i,
    r"jailbreak"i,
]

function sanitize_shell_command(cmd::String)::Result{String, SecurityError}
    # TODO: Implement strict shell sanitization
    # 1. Check against forbidden patterns
    # 2. Validate against allowlist of safe commands
    # 3. Escape all special characters
    # 4. Log suspicious attempts
end

function sanitize_path(path::String, allowed_dirs::Vector{String})::Result{String, SecurityError}
    # TODO: Implement path traversal prevention
    # 1. Resolve to absolute path
    # 2. Check for ".." (directory traversal)
    # 3. Verify path starts with allowed directory
    # 4. Check file permissions
end

function detect_injection(text::String)::Union{InjectionAttempt, Nothing}
    # TODO: Detect prompt injection attempts
    # 1. Check against known patterns
    # 2. Use heuristics (e.g., sudden topic change)
    # 3. Flag for human review if detected
    # 4. Return InjectionAttempt with severity level
end

end # module
```

**Success Criteria:**
- [ ] Zero shell injection vulnerabilities
- [ ] Path traversal completely blocked
- [ ] Prompt injection detection rate >90%
- [ ] All security tests passing
- [ ] Security score: 70/100+

---

## Phase 2: Enhanced Learning & Cognition (Priority: HIGH)

### Task 2.1: Implement RUDDER for Delayed Rewards

**File:** `adaptive-kernel/cognition/learning/RUDDER.jl`

```julia
# Implement RUDDER (Return Decomposition for Delayed Rewards)
# This solves the temporal credit assignment problem
# Reference: https://arxiv.org/abs/1806.07857

using Flux
using CUDA  # Optional: GPU acceleration

struct RUDDERModel
    lstm::LSTM              # Sequence model for episode analysis
    reward_predictor::Chain # Maps LSTM hidden state to reward contribution
    optimizer::Flux.Optimise.AbstractOptimiser
end

# TODO: Implement RUDDER algorithm:

function create_rudder_model(state_dim::Int, hidden_dim::Int=128)::RUDDERModel
    # Create LSTM to process episode sequences
    # Create reward predictor network
    # Initialize optimizer
end

function train_rudder!(model::RUDDERModel, episodes::Vector{Episode})
    # For each episode:
    # 1. Forward pass through LSTM to get hidden states
    # 2. Predict reward contribution at each timestep
    # 3. Compute loss: difference between predicted and actual returns
    # 4. Backpropagate and update
end

function redistribute_rewards(model::RUDDERModel, episode::Episode)::Vector{Float32}
    # Given an episode, return redistributed rewards for each step
    # This allows immediate credit assignment instead of waiting for episode end
end

# Integration with existing brain:
function update_policy_with_rudder!(brain::Brain, episode::Episode)
    # 1. Use RUDDER to get immediate rewards for each step
    # 2. Update policy using these redistributed rewards
    # 3. Also update RUDDER model itself
end
```

**Success Criteria:**
- [ ] 10x faster learning on delayed reward tasks
- [ ] Episode sequences correctly processed
- [ ] Reward redistribution working
- [ ] Integration with existing RL loop
- [ ] Cognitive score: 60/100+

---

### Task 2.2: Advanced Goal System

**File:** `adaptive-kernel/cognition/goals/GoalSystem.jl`

```julia
# Enhanced autonomous goal generation and management
# Requirements:
# - Hierarchical goals (strategic → tactical → operational)
# - Goal decomposition (break complex goals into subgoals)
# - Priority adjustment based on context
# - Goal completion detection
# - Learning from goal success/failure

using DataStructures

struct Goal
    id::UUID
    description::String
    priority::Float32
    parent_goal::Union{UUID, Nothing}
    subgoals::Vector{UUID}
    status::Symbol  # :pending, :active, :completed, :failed, :abandoned
    created_at::DateTime
    deadline::Union{DateTime, Nothing}
    success_criteria::Function
    estimated_reward::Float32
end

mutable struct GoalSystem
    goals::Dict{UUID, Goal}
    active_goals::PriorityQueue{UUID, Float32}
    goal_history::Vector{GoalOutcome}
end

# TODO: Implement advanced goal management:

function propose_goal(system::GoalSystem, description::String, context::Context)::Goal
    # Use LLM to analyze description and context
    # Generate success criteria
    # Estimate priority and reward
    # Decompose into subgoals if complex
end

function decompose_goal(goal::Goal, llm::LLMBridge)::Vector{Goal}
    # Use LLM to break complex goal into subgoals
    # Create dependency graph
    # Assign priorities to subgoals
end

function select_next_goal(system::GoalSystem, world_state::WorldState)::Union{Goal, Nothing}
    # Consider:
    # - Goal priority
    # - Current context (energy, time, resources)
    # - Dependencies (must complete parent goals first)
    # - Deadline urgency
    # Return highest-value goal or nothing
end

function evaluate_goal_completion(goal::Goal, outcome::ActionOutcome)::Bool
    # Check if success criteria met
    # Update goal status
    # Learn from success/failure
    # Adjust future goal priorities
end

function learn_from_goal_outcomes(system::GoalSystem)
    # Analyze goal history
    # Identify patterns in successful vs failed goals
    # Adjust goal generation strategy
    # Update priority estimation model
end
```

**Success Criteria:**
- [ ] Autonomous goal generation from user intent
- [ ] Complex goals decomposed into 3+ subgoals
- [ ] Goal completion rate >70%
- [ ] Learning from outcomes demonstrated
- [ ] Cognitive score: 70/100+

---

### Task 2.3: World Model with Prediction

**File:** `adaptive-kernel/cognition/worldmodel/WorldModel.jl`

```julia
# Predictive world model for planning and simulation
# Requirements:
# - Predict next state given current state and action
# - Uncertainty estimation
# - Multi-step rollouts for planning
# - Model-based reinforcement learning

using Flux

struct WorldModel
    transition_model::Chain  # Predicts s_{t+1} from s_t and a_t
    reward_model::Chain      # Predicts r_t from s_t and a_t
    uncertainty_model::Chain # Predicts epistemic uncertainty
    observation_buffer::CircularBuffer
end

# TODO: Implement predictive world model:

function create_world_model(state_dim::Int, action_dim::Int)::WorldModel
    # Create neural networks for transition, reward, uncertainty
    # Initialize observation buffer
end

function predict_next_state(model::WorldModel, state::Vector{Float32}, 
                            action::Int)::Tuple{Vector{Float32}, Float32}
    # Forward pass through transition model
    # Also compute uncertainty
    # Return (predicted_next_state, uncertainty)
end

function update_world_model!(model::WorldModel, transition::Transition)
    # Update transition model with actual transition
    # Update reward model
    # Update uncertainty model
    # Use experience replay for stability
end

function plan_with_rollouts(model::WorldModel, state::Vector{Float32}, 
                            depth::Int=5)::Vector{Action}
    # Use world model to simulate future trajectories
    # Try different action sequences
    # Return best sequence according to predicted rewards
    # Consider uncertainty (don't trust uncertain predictions)
end

function model_based_learning!(brain::Brain, world_model::WorldModel)
    # Generate synthetic experiences using world model
    # Train policy on both real and synthetic experiences
    # This is Dyna-Q style model-based RL
end
```

**Success Criteria:**
- [ ] Accurate next-state prediction (>80% accuracy)
- [ ] Uncertainty calibration working
- [ ] 5-step rollout planning functional
- [ ] Improved sample efficiency vs model-free
- [ ] Cognitive score: 75/100+

---

## Phase 3: Production Hardening (Priority: HIGH)

### Task 3.1: Memory Management & Leak Prevention

**File:** `adaptive-kernel/kernel/MemoryManager.jl`

```julia
# Prevent memory leaks in long-running system
# Requirements:
# - Monitor memory usage continuously
# - Prune old memories automatically
# - Clear caches when memory pressure high
# - GC tuning for Julia runtime
# - Memory budgets per component

using Logging

mutable struct MemoryManager
    max_total_memory::Int  # Bytes
    memory_budgets::Dict{Symbol, Int}  # Per-component budgets
    cleanup_threshold::Float32  # Trigger cleanup at 80% usage
end

# TODO: Implement memory management:

function monitor_memory_usage(manager::MemoryManager)
    @async while true
        current = get_current_memory_usage()
        if current > manager.max_total_memory * manager.cleanup_threshold
            @warn "Memory pressure detected" current max=manager.max_total_memory
            trigger_cleanup!(manager)
        end
        sleep(60)  # Check every minute
    end
end

function trigger_cleanup!(manager::MemoryManager)
    # 1. Prune old episodic memories (keep only recent + important)
    prune_memories!()
    
    # 2. Clear caches
    empty!(action_cache)
    empty!(llm_response_cache)
    
    # 3. Compact data structures
    compact_goal_history!()
    
    # 4. Force garbage collection
    GC.gc()
    
    # 5. Log cleanup results
    new_usage = get_current_memory_usage()
    @info "Cleanup complete" before=current after=new_usage freed=(current-new_usage)
end

function prune_memories!(memory_system::SemanticMemory, keep_count::Int=1000)
    # Keep only:
    # - Recent memories (last 100)
    # - Important memories (high reward episodes)
    # - Random sample for diversity
end

function set_gc_parameters()
    # Tune Julia GC for long-running operation
    # Reduce GC frequency but increase thoroughness
    # Prevent GC thrashing
end
```

**Success Criteria:**
- [ ] 168+ hour continuous operation (1 week)
- [ ] Memory usage stable (<1GB)
- [ ] No memory leaks detected
- [ ] GC pauses <100ms
- [ ] Production readiness: 60/100+

---

### Task 3.2: Comprehensive Error Handling

**File:** `adaptive-kernel/kernel/ErrorRecovery.jl`

```julia
# Robust error handling and recovery strategies
# Requirements:
# - Classify errors (critical vs recoverable)
# - Recovery strategies per error type
# - Circuit breaker pattern
# - Automatic retry with exponential backoff
# - Human notification for critical errors

using Dates

abstract type SystemError end
struct CriticalError <: SystemError
    message::String
    source::Symbol
    timestamp::DateTime
end

struct RecoverableError <: SystemError
    message::String
    recovery_strategy::Symbol
end

# TODO: Implement error recovery:

function safe_execute(f::Function, recovery_strategy::Symbol=:retry)
    try
        return f()
    catch e
        error_type = classify_error(e)
        
        if error_type isa CriticalError
            enter_safe_mode!()
            notify_human(error_type)
            rethrow(e)
        else
            return apply_recovery(error_type, recovery_strategy)
        end
    end
end

function classify_error(e::Exception)::SystemError
    # Classify based on exception type and message
    # CriticalError: IPC failure, crypto failure, kernel panic
    # RecoverableError: timeout, rate limit, API error
end

function apply_recovery(error::RecoverableError, strategy::Symbol)
    if strategy == :retry
        return retry_with_backoff(() -> error.original_operation)
    elseif strategy == :fallback
        return use_fallback_method()
    elseif strategy == :skip
        @warn "Skipping failed operation" error
        return nothing
    end
end

function retry_with_backoff(f::Function, max_attempts::Int=5)
    for attempt in 1:max_attempts
        try
            return f()
        catch e
            if attempt == max_attempts
                rethrow(e)
            end
            wait_time = 2^attempt  # Exponential backoff
            @info "Retrying operation" attempt wait_time
            sleep(wait_time)
        end
    end
end

# Circuit breaker pattern
mutable struct CircuitBreaker
    failure_threshold::Int
    failure_count::Int
    state::Symbol  # :closed, :open, :half_open
    last_failure::DateTime
end

function call_with_circuit_breaker(breaker::CircuitBreaker, f::Function)
    if breaker.state == :open
        # Don't even try if circuit is open
        if now() - breaker.last_failure > Minute(5)
            breaker.state = :half_open
        else
            throw(CircuitOpenError())
        end
    end
    
    try
        result = f()
        breaker.failure_count = 0
        breaker.state = :closed
        return result
    catch e
        breaker.failure_count += 1
        breaker.last_failure = now()
        
        if breaker.failure_count >= breaker.failure_threshold
            breaker.state = :open
            @warn "Circuit breaker opened" breaker.failure_count
        end
        rethrow(e)
    end
end
```

**Success Criteria:**
- [ ] All critical errors handled gracefully
- [ ] Automatic recovery from transient failures
- [ ] Circuit breakers prevent cascading failures
- [ ] Zero crashes in 24-hour stress test
- [ ] Production readiness: 70/100+

---

## Phase 4: Advanced Features (Priority: MEDIUM)

### Task 4.1: Multi-Agent Debate Engine

**File:** `Itheris/Brain/Src/debate.rs`

```rust
// Implement sophisticated multi-agent debate for better decisions
// Requirements:
// - Multiple specialized agents (Strategist, Critic, Scout, Executor)
// - Structured debate protocol
// - Consensus mechanism
// - Disagreement detection and resolution

use std::collections::HashMap;

#[derive(Clone, Copy)]
pub enum AgentRole {
    Strategist,  // Long-term planning
    Critic,      // Risk assessment
    Scout,       // Information gathering
    Executor,    // Practical implementation
}

pub struct DebateAgent {
    role: AgentRole,
    model: Box<dyn DecisionModel>,
    vote_weight: f32,
}

pub struct DebateEngine {
    agents: Vec<DebateAgent>,
    consensus_threshold: f32,
    max_debate_rounds: usize,
}

impl DebateEngine {
    // TODO: Implement debate protocol:
    
    pub fn conduct_debate(&mut self, proposal: &Proposal) -> DebateOutcome {
        // 1. Each agent analyzes proposal independently
        // 2. Agents share their assessments
        // 3. If disagreement detected, conduct debate rounds
        // 4. Agents can change their position based on arguments
        // 5. Continue until consensus or max rounds reached
        // 6. Return final decision with confidence level
        todo!()
    }
    
    fn detect_disagreement(&self, votes: &HashMap<AgentRole, Vote>) -> bool {
        // Check if agents significantly disagree
        // Return true if variance in votes > threshold
        todo!()
    }
    
    fn debate_round(&mut self, proposal: &Proposal, round: usize) {
        // Each agent presents arguments
        // Agents can counter-argue
        // Agents update their positions
        todo!()
    }
    
    fn reach_consensus(&self, votes: &HashMap<AgentRole, Vote>) -> Option<Decision> {
        // Weighted voting based on agent roles
        // Return decision if consensus reached
        todo!()
    }
}
```

**Success Criteria:**
- [ ] 4 specialized agents implemented
- [ ] Debate improves decision quality (measured by rewards)
- [ ] Consensus reached in <5 rounds typically
- [ ] Disagreements properly resolved
- [ ] Cognitive score: 80/100+

---

### Task 4.2: Semantic Memory with RAG

**File:** `adaptive-kernel/cognition/memory/SemanticMemory.jl`

```julia
# Semantic memory with Retrieval-Augmented Generation
# Requirements:
# - Vector embeddings for all experiences
# - Efficient similarity search (HNSW or FAISS)
# - Memory consolidation (episodic → semantic)
# - Forgetting mechanism (decay unimportant memories)
# - RAG for context injection into LLM

using LinearAlgebra
using HNSW  # Or Faiss.jl

struct Memory
    embedding::Vector{Float32}
    content::String
    importance::Float32
    created_at::DateTime
    last_accessed::DateTime
    access_count::Int
end

mutable struct SemanticMemory
    embeddings::HNSWIndex
    memories::Dict{Int, Memory}
    embedding_model::EmbeddingModel
end

# TODO: Implement semantic memory:

function store_memory!(mem::SemanticMemory, content::String, importance::Float32)
    # 1. Generate embedding using embedding model
    # 2. Add to vector index
    # 3. Store memory metadata
    # 4. Update importance based on relevance to goals
end

function retrieve_relevant(mem::SemanticMemory, query::String, k::Int=5)::Vector{Memory}
    # 1. Generate query embedding
    # 2. Search vector index for nearest neighbors
    # 3. Update access counts and timestamps
    # 4. Return top-k most relevant memories
end

function consolidate_memories!(mem::SemanticMemory)
    # Memory consolidation (like sleep in biological brains)
    # 1. Identify frequently accessed episodic memories
    # 2. Merge similar memories
    # 3. Strengthen important connections
    # 4. Decay unimportant memories (reduce importance scores)
end

function forget_unimportant!(mem::SemanticMemory)
    # Forgetting mechanism
    # 1. Find memories with low importance and few accesses
    # 2. Remove from index
    # 3. Free memory
    # Keep memory usage bounded
end

function augment_with_context(mem::SemanticMemory, prompt::String)::String
    # RAG: Retrieve relevant memories and inject into prompt
    # 1. Retrieve relevant memories for prompt
    # 2. Format as context
    # 3. Prepend to prompt
    # 4. Return augmented prompt
end
```

**Success Criteria:**
- [ ] 10,000+ memories stored efficiently
- [ ] Sub-100ms retrieval time
- [ ] Memory consolidation working
- [ ] RAG improves LLM responses
- [ ] Cognitive score: 85/100+

---

## Phase 5: Integration & Testing (Priority: CRITICAL)

### Task 5.1: End-to-End Integration Tests

**File:** `adaptive-kernel/tests/integration_test.jl`

```julia
# Comprehensive integration tests for full system
# Requirements:
# - Test complete user request → response flow
# - Test all component interactions
# - Test failure modes and recovery
# - Test long-running scenarios
# - Performance benchmarks

using Test

@testset "End-to-End Integration" begin
    
    @testset "User Request Flow" begin
        # Initialize full system
        system = initialize_itheris()
        
        # User: "Check my CPU usage"
        result = process_request(system, "Check my CPU usage")
        
        # Verify complete flow:
        @test result.llm_understood == true
        @test result.brain_proposed != nothing
        @test result.kernel_approved == true
        @test result.action_executed == true
        @test contains(result.response, "CPU")
    end
    
    @testset "Multi-Step Task" begin
        system = initialize_itheris()
        
        # Complex task requiring multiple actions
        result = process_request(system, "Find all log files with errors and summarize them")
        
        # Should:
        # 1. Search for log files
        # 2. Read each file
        # 3. Filter for errors
        # 4. Summarize
        @test length(result.actions_taken) >= 3
        @test all(a -> a.approved, result.actions_taken)
    end
    
    @testset "Fail-Closed on Brain Disconnect" begin
        system = initialize_itheris()
        
        # Disconnect brain
        disconnect_brain!(system)
        
        # Try to execute action
        result = process_request(system, "Write a file")
        
        # Should fail-closed
        @test result.kernel_approved == false
        @test result.reason == "Brain unavailable - fail-closed"
        @test system.mode == :SAFE_MODE
    end
    
    @testset "Recovery from Brain Reconnect" begin
        system = initialize_itheris()
        disconnect_brain!(system)
        
        @test system.mode == :SAFE_MODE
        
        # Reconnect
        reconnect_brain!(system)
        
        # Should exit safe mode
        @test system.mode == :NORMAL
        
        # Should work again
        result = process_request(system, "What's my energy level?")
        @test result.success == true
    end
    
    @testset "Learning from Feedback" begin
        system = initialize_itheris()
        
        # Execute action
        result1 = process_request(system, "Test action")
        initial_confidence = result1.brain_confidence
        
        # Provide positive feedback
        provide_feedback!(system, result1.action_id, reward=1.0)
        
        # Execute similar action
        result2 = process_request(system, "Test action")
        
        # Confidence should increase
        @test result2.brain_confidence > initial_confidence
    end
    
end

@testset "Performance Benchmarks" begin
    
    @testset "IPC Throughput" begin
        system = initialize_itheris()
        
        # Measure messages per second
        start_time = time()
        for i in 1:10000
            send_proposal(system.brain, create_test_proposal())
            receive_verdict(system.kernel)
        end
        elapsed = time() - start_time
        
        throughput = 10000 / elapsed
        @test throughput > 1000  # At least 1000 msg/sec
    end
    
    @testset "Memory Usage" begin
        system = initialize_itheris()
        
        initial_memory = get_memory_usage()
        
        # Run for 1 hour simulated time
        for i in 1:3600
            process_request(system, "Test request $i")
        end
        
        final_memory = get_memory_usage()
        memory_growth = final_memory - initial_memory
        
        # Should not grow significantly
        @test memory_growth < 100_000_000  # Less than 100MB growth
    end
    
end
```

**Success Criteria:**
- [ ] All integration tests passing
- [ ] IPC throughput >1000 msg/sec
- [ ] Memory stable over 1hr test
- [ ] Recovery from all failure modes
- [ ] Overall score: 75/100+

---

## Implementation Guidelines

### Code Quality Standards

1. **Type Stability** (Julia)
   - Use concrete types everywhere
   - Avoid type instability (use `@code_warntype` to check)
   - Proper function signatures

2. **Memory Safety** (Rust)
   - No unsafe blocks unless absolutely necessary
   - Proper lifetime annotations
   - Use Arc/Mutex for shared state

3. **Error Handling**
   - Never use `panic!` in Rust (return Result)
   - Always handle errors in Julia (try-catch)
   - Log errors with context

4. **Testing**
   - Unit tests for all functions
   - Integration tests for components
   - Property-based tests where applicable
   - Minimum 80% code coverage

5. **Documentation**
   - Docstrings for all public functions
   - Architecture decision records (ADR)
   - Update STATUS.md with maturity scores
   - README examples

### Performance Targets

- **Latency:** User request → response in <500ms
- **Throughput:** 1000+ IPC messages/second
- **Memory:** <1GB total (Julia + Rust combined)
- **Uptime:** 168+ hours continuous operation
- **Learning:** Measurable improvement over 100 episodes

### Security Requirements

- **Input Validation:** All user inputs sanitized
- **Cryptographic:** HMAC-SHA256 for all actions
- **Audit Logging:** All actions logged immutably
- **Principle of Least Privilege:** Capabilities restricted by default
- **Fail-Closed:** System halts on security failures

---

## Success Metrics

### Target Maturity Scores

| Component | Current | Target |
|-----------|---------|--------|
| Security | 12/100 | 80/100 |
| IPC Stability | 30/100 | 90/100 |
| Learning | 35/100 | 75/100 |
| Cognition | 47/100 | 85/100 |
| Production | 25/100 | 80/100 |
| **Overall** | **43/100** | **80/100** |

### Milestone Checklist

**Phase 1 Complete:**
- [ ] Rust-Julia IPC working flawlessly
- [ ] 24+ hour continuous operation
- [ ] Cryptographic signatures implemented
- [ ] Input sanitization complete
- [ ] Security score: 70/100+

**Phase 2 Complete:**
- [ ] RUDDER learning operational
- [ ] Advanced goal system working
- [ ] World model predictions accurate
- [ ] Cognitive score: 75/100+

**Phase 3 Complete:**
- [ ] No memory leaks in 1-week test
- [ ] Error recovery fully automated
- [ ] Production score: 75/100+

**Phase 4 Complete:**
- [ ] Multi-agent debate functional
- [ ] Semantic memory with RAG
- [ ] Cognitive score: 85/100+

**Phase 5 Complete:**
- [ ] All integration tests passing
- [ ] Performance benchmarks met
- [ ] Overall score: 80/100+

---

## Final Notes for Coding Agent

**Priorities:**
1. **CRITICAL:** Fix IPC first - nothing else works without it
2. **CRITICAL:** Security hardening - too many vulnerabilities
3. **HIGH:** Memory management - prevent leaks
4. **HIGH:** Error handling - production robustness
5. **MEDIUM:** Advanced learning (RUDDER, goals, world model)

**Development Approach:**
- Implement incrementally - test each component thoroughly
- Keep existing tests passing
- Update STATUS.md after each major component
- Add new tests for new features
- Document all architectural decisions

**Testing Strategy:**
- Run tests after every significant change
- Use `julia --project=. -e 'using Pkg; Pkg.test()'`
- Run security diagnostics: `julia diagnose_vulnerabilities.jl`
- Monitor memory during development

**When in Doubt:**
- Prefer security over convenience
- Prefer fail-closed over fail-open
- Prefer simple over clever
- Prefer tested over optimized

---

**End of Implementation Prompt**

This prompt provides complete specifications for transforming ITHERIS from 43/100 to 80/100+ maturity. Follow the phases in order, test thoroughly, and update documentation as you go.

Good luck building the future of sovereign AI! 🚀