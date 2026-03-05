# test_circuit_breaker.jl - Comprehensive tests for Circuit Breaker
#
# Tests the circuit breaker pattern under various failure conditions
# to ensure proper behavior for system resilience.

using Test
using Dates

# Add parent directory to path for imports
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Import Resilience module which includes CircuitBreaker
include(joinpath(@__DIR__, "..", "resilience", "Resilience.jl"))
using ..Resilience

# Get references to the circuit breaker components
const CircuitBreaker = Resilience.CircuitBreaker
const CircuitBreakerRegistry = Resilience.CircuitBreakerRegistry
const CircuitBreakerOpenError = Resilience.CircuitBreakerOpenError
const CircuitState = Resilience.CircuitState
const call = Resilience.call
const reset! = Resilience.reset!
const get_state = Resilience.get_state
const is_available = Resilience.is_available
const get_breaker = Resilience.get_breaker
const with_circuit = Resilience.with_circuit
const is_breaker_available = Resilience.is_breaker_available
const get_breaker_state = Resilience.get_breaker_state
const get_all_breaker_states = Resilience.get_all_breaker_states
const create_standard_breakers = Resilience.create_standard_breakers
const _on_success = Resilience._on_success
const _on_failure = Resilience._on_failure

# State constants (renamed for test compatibility)
const CLOSED = Resilience.CB_CLOSED
const OPEN = Resilience.CB_OPEN
const HALF_OPEN = Resilience.CB_HALF_OPEN

# ============================================================================
# Test 1: Basic Circuit Breaker Creation
# ============================================================================

@testset "Circuit Breaker Creation" begin
    # Test default creation
    cb = CircuitBreaker("test"; threshold=3, timeout=10)
    @test cb.name == "test"
    @test cb.state == CLOSED
    @test cb.failure_count == 0
    @test cb.success_count == 0
    @test cb.threshold == 3
    @test cb.timeout == 10
end

# ============================================================================
# Test 2: Circuit Breaker Opens After Threshold
# ============================================================================

@testset "Circuit Opens After Threshold" begin
    cb = CircuitBreaker("test_open"; threshold=3, timeout=60)
    
    # Simulate failures
    for i in 1:3
        _on_failure(cb)
    end
    
    @test cb.failure_count == 3
    @test cb.state == OPEN
    @test !is_available(cb)
end

# ============================================================================
# Test 3: Circuit Stays Closed Below Threshold
# ============================================================================

@testset "Circuit Stays Closed Below Threshold" begin
    cb = CircuitBreaker("test_closed"; threshold=5, timeout=60)
    
    # Simulate failures below threshold
    for i in 1:2
        _on_failure(cb)
    end
    
    @test cb.failure_count == 2
    @test cb.state == CLOSED
    @test is_available(cb)
end

# ============================================================================
# Test 4: Successful Calls Reset Failure Count
# ============================================================================

@testset "Successful Calls Reset Failure Count" begin
    cb = CircuitBreaker("test_reset"; threshold=3, timeout=60)
    
    # Add some failures
    _on_failure(cb)
    _on_failure(cb)
    @test cb.failure_count == 2
    
    # Add success
    _on_success(cb)
    
    @test cb.failure_count == 0
    @test cb.state == CLOSED
end

# ============================================================================
# Test 5: Circuit Transitions to Half-Open After Timeout
# ============================================================================

@testset "Circuit Transitions to Half-Open After Timeout" begin
    cb = CircuitBreaker("test_half_open"; threshold=2, timeout=1)
    
    # Open the circuit
    _on_failure(cb)
    _on_failure(cb)
    @test cb.state == OPEN
    
    # Wait for timeout (in real scenario, this would be time-based)
    # For testing, we manually set the last_state_change
    cb.last_state_change = now() - Dates.Second(2)
    
    # Check if available now (should transition to HALF_OPEN)
    @test is_available(cb)
end

# ============================================================================
# Test 6: Successful Recovery Closes Circuit
# ============================================================================

@testset "Successful Recovery Closes Circuit" begin
    cb = CircuitBreaker("test_recovery"; threshold=2, timeout=1)
    
    # Open and transition to half-open
    _on_failure(cb)
    _on_failure(cb)
    @test cb.state == OPEN
    
    cb.last_state_change = now() - Dates.Second(2)
    @test is_available(cb)
    @test cb.state == HALF_OPEN
    
    # Multiple successful calls to close
    _on_success(cb)
    @test cb.success_count == 1
    @test cb.state == HALF_OPEN
    
    _on_success(cb)
    @test cb.success_count == 2
    @test cb.state == HALF_OPEN
    
    _on_success(cb)
    @test cb.success_count >= 3
    @test cb.state == CLOSED
end

# ============================================================================
# Test 7: Circuit Breaker Registry
# ============================================================================

@testset "Circuit Breaker Registry" begin
    registry = CircuitBreakerRegistry(;threshold=5, timeout=30)
    
    # Get non-existent breaker (should create)
    cb1 = get_breaker(registry, "service1")
    @test cb1 !== nothing
    @test cb1.name == "service1"
    @test cb1.threshold == 5
    
    # Get existing breaker (should return same)
    cb2 = get_breaker(registry, "service1")
    @test cb1 === cb2
    
    # Create with custom threshold
    cb3 = get_breaker(registry, "service2"; threshold=10)
    @test cb3.threshold == 10
    
    # Check all states
    states = get_all_breaker_states(registry)
    @test haskey(states, "service1")
    @test haskey(states, "service2")
end

# ============================================================================
# Test 8: Circuit Breaker Call with Function
# ============================================================================

@testset "Circuit Breaker Call with Function" begin
    cb = CircuitBreaker("test_call"; threshold=2, timeout=60)
    
    # Successful call
    result = call(cb, () -> 42)
    @test result == 42
    @test cb.success_count == 1
    @test cb.state == CLOSED
    
    # Test with function that fails
    fail_count = Ref(0)
    function failing_func()
        fail_count[] += 1
        error("Test failure")
    end
    
    # First failure
    @test_throws ErrorException call(cb, failing_func)
    @test cb.failure_count == 1
    @test cb.state == CLOSED
    
    # Second failure - should open
    @test_throws ErrorException call(cb, failing_func)
    @test cb.failure_count == 2
    @test cb.state == OPEN
    
    # Third call should throw CircuitBreakerOpenError
    @test_throws CircuitBreakerOpenError call(cb, () -> 42)
end

# ============================================================================
# Test 9: Manual Reset
# ============================================================================

@testset "Manual Reset" begin
    cb = CircuitBreaker("test_manual_reset"; threshold=2, timeout=60)
    
    # Open the circuit
    _on_failure(cb)
    _on_failure(cb)
    @test cb.state == OPEN
    
    # Manual reset
    reset!(cb)
    
    @test cb.state == CLOSED
    @test cb.failure_count == 0
    @test cb.success_count == 0
end

# ============================================================================
# Test 10: Concurrent Access (Basic)
# ============================================================================

@testset "Concurrent Access (Basic)" begin
    cb = CircuitBreaker("test_concurrent"; threshold=10, timeout=60)
    
    # Simulate concurrent access (simplified)
    @test is_available(cb)
    
    # Sequential failures - need 10 to open
    for i in 1:10
        _on_failure(cb)
    end
    
    @test cb.failure_count == 10
    @test cb.state == OPEN  # threshold was 10
end

# ============================================================================
# Test 11: Standard Breakers Creation
# ============================================================================

@testset "Standard Breakers Creation" begin
    registry = CircuitBreakerRegistry()
    create_standard_breakers(registry)
    
    # Check standard breakers exist
    @test haskey(registry.breakers, "itheris")
    @test haskey(registry.breakers, "http_api")
    @test haskey(registry.breakers, "llm_api")
    @test haskey(registry.breakers, "service_manager")
    @test haskey(registry.breakers, "ipc")
    
    # Check custom thresholds
    @test registry.breakers["itheris"].threshold == 3
    @test registry.breakers["llm_api"].timeout == 120
end

# ============================================================================
# Test 12: Circuit Breaker Integration - IPC Pattern
# ============================================================================

@testset "Circuit Breaker Integration Pattern - IPC" begin
    # Simulate IPC-like usage
    registry = CircuitBreakerRegistry(;threshold=3, timeout=30)
    get_breaker(registry, "itheris")
    
    # Simulate IPC communication
    function simulate_ipc_call()
        # In real usage, this would call RustIPC
        return "response"
    end
    
    # Successful calls
    result = with_circuit(registry, "itheris", simulate_ipc_call)
    @test result == "response"
    
    # Check state
    state = get_breaker_state(registry, "itheris")
    @test state == CLOSED
end

# ============================================================================
# Test 13: Circuit Breaker Integration - HTTP Pattern
# ============================================================================

@testset "Circuit Breaker Integration Pattern - HTTP" begin
    # Simulate HTTP-like usage
    registry = CircuitBreakerRegistry(;threshold=5, timeout=60)
    get_breaker(registry, "http_api")
    
    # Simulate HTTP request
    function simulate_http_request(url::String)
        return "content from $url"
    end
    
    # Successful call
    result = with_circuit(registry, "http_api", simulate_http_request, "httpbin.org")
    @test result == "content from httpbin.org"
    
    # Verify available
    @test is_breaker_available(registry, "http_api")
end

# ============================================================================
# Test Summary
# ============================================================================

println("\n" * "="^60)
println("CIRCUIT BREAKER TEST SUMMARY")
println("="^60)
println("All circuit breaker patterns tested:")
println("  ✓ Basic creation and configuration")
println("  ✓ Opening after threshold failures")
println("  ✓ Staying closed below threshold")
println("  ✓ Success resets failure count")
println("  ✓ Half-open transition after timeout")
println("  ✓ Successful recovery closes circuit")
println("  ✓ Registry for multiple breakers")
println("  ✓ Call wrapper with function execution")
println("  ✓ Manual reset functionality")
println("  ✓ Standard breaker configurations")
println("  ✓ IPC integration pattern")
println("  ✓ HTTP integration pattern")
println("="^60)
