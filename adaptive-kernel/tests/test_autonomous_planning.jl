# tests/test_autonomous_planning.jl - Test autonomous planning functionality

using Test
using Dates
using UUIDs

# Include the module we're testing
include("../planning/AutonomousPlanner.jl")
using .AutonomousPlanner

# Import enum values for testing
import .AutonomousPlanner: discovery, foundation, deep_dive, application

# ============================================================================
# TEST SUITE
# ============================================================================

@testset "Topic Decomposition Tests" begin
    # Test default topic decomposition
    decomposition = decompose_topic("Machine Learning")
    
    @test decomposition.topic == "Machine Learning"
    @test length(decomposition.modules) == 4
    @test decomposition.estimated_total_duration_minutes == 110
    @test all(d -> d >= 0.2f0 && d <= 0.6f0, decomposition.difficulty_curve)
end

@testset "Tunisia Topic Decomposition" begin
    # Test Tunisia-specific decomposition
    decomposition = decompose_topic("Tunisia")
    
    @test decomposition.topic == "Tunisia"
    @test length(decomposition.modules) == 4
    
    # Verify module titles
    titles = [m.title for m in decomposition.modules]
    @test "Geography & Location" in titles
    @test "History & Ancient Civilizations" in titles
    @test "Modern Politics & Society" in titles
    @test "Culture & Economy" in titles
    
    # Verify phases (using enum values directly)
    phases = [m.phase for m in decomposition.modules]
    @test discovery in phases
    @test foundation in phases
    @test deep_dive in phases
    @test application in phases
end

@testset "Learning Plan Creation Tests" begin
    plan = create_learning_plan("Tunisia")
    
    @test plan.topic == "Tunisia"
    @test plan.status == :active
    @test length(plan.modules) == 4
    @test plan.total_progress == 0.0f0
    
    # Verify Socratic challenge was created
    @test length(plan.socratic_challenges) == 1
    
    socratic = first(plan.socratic_challenges)
    @test socratic.status == :scheduled
    @test socratic.duration_minutes == SOCRATIC_CHALLENGE_DURATION_MINUTES
end

@testset "Module Dependencies Tests" begin
    plan = create_learning_plan("Python Programming")
    
    # First module should have no dependencies
    @test isempty(plan.modules[1].dependencies)
    
    # Subsequent modules should depend on previous
    @test length(plan.modules[2].dependencies) == 1
    @test plan.modules[2].dependencies[1] == plan.modules[1].id
    
    @test length(plan.modules[3].dependencies) == 2
end

@testset "Get Next Module Tests" begin
    plan = create_learning_plan("Tunisia")
    
    next_mod = get_next_module!(plan)
    @test next_mod !== nothing
    @test next_mod.title == "Geography & Location"
    @test next_mod.status == :pending
    
    # Simulate starting the module
    update_module_progress!(plan, next_mod.id, 0.5f0)
    
    # Check status updated
    @test next_mod.status == :in_progress
    @test next_mod.progress == 0.5f0
    
    # Complete the module
    update_module_progress!(plan, next_mod.id, 1.0f0)
    
    # Check next module is now first
    next_mod2 = get_next_module!(plan)
    @test next_mod2.title == "History & Ancient Civilizations"
end

@testset "Socratic Challenge Question Bank" begin
    plan = create_learning_plan("Tunisia")
    socratic = first(plan.socratic_challenges)
    
    # Question bank should have questions
    @test length(socratic.question_bank) > 0
    
    # Questions should reference module titles
    for q in socratic.question_bank
        @test occursin("Geography", q) || 
              occursin("History", q) || 
              occursin("Modern", q) || 
              occursin("Culture", q)
    end
end

@testset "Plan Status Tests" begin
    plan = create_learning_plan("Tunisia")
    
    status = get_plan_status(plan)
    
    @test status["topic"] == "Tunisia"
    @test status["status"] == "active"
    @test status["total_progress"] == 0.0
    @test status["modules"]["total"] == 4
    @test status["modules"]["completed"] == 0
    @test status["modules"]["pending"] == 4
    @test status["next_module"] !== nothing
    @test status["next_socratic"] !== nothing
end

@testset "Generate Learning Journey Tests" begin
    response = generate_learning_journey("Tunisia")
    
    @test response["autonomous"] == true
    @test response["topic"] == "Tunisia"
    @test response["module_count"] == 4
    @test haskey(response, "message")
    @test haskey(response, "plan_id")
    @test haskey(response, "socratic_challenge")
    
    # Message should contain key phrases
    msg = response["message"]
    @test occursin("Tunisia", msg)
    @test occursin("4-module", msg) || occursin("4 module", msg)
    @test occursin("Socratic Challenge", msg)
end

@testset "Create Autonomous Response Tests" begin
    plan = create_learning_plan("Quantum Computing")
    response = create_autonomous_response(plan)
    
    @test response["autonomous"] == true
    @test response["topic"] == "Quantum Computing"
    @test response["module_count"] == 4
    
    # Should contain message
    @test haskey(response, "message")
    
    # Should have socratic challenge
    @test response["socratic_challenge"] !== nothing
end

# ============================================================================
# RUN ALL TESTS
# ============================================================================

println("\n" * "="^60)
println("AUTONOMOUS PLANNING TEST SUITE")
println("="^60 * "\n")

# Run tests
Test.@testset verbose=true "AutonomousPlanner" begin
    # Topic Decomposition Tests
    println("Running topic decomposition tests...")
    
    # Tunisia tests
    decomposition = decompose_topic("Tunisia")
    @test decomposition.topic == "Tunisia"
    @test length(decomposition.modules) == 4
    
    titles = [m.title for m in decomposition.modules]
    @test "Geography & Location" in titles
    
    # Learning Plan tests
    println("Running learning plan tests...")
    plan = create_learning_plan("Tunisia")
    @test plan.topic == "Tunisia"
    @test length(plan.modules) == 4
    
    # Socratic Challenge tests
    println("Running Socratic challenge tests...")
    socratic = first(plan.socratic_challenges)
    @test socratic.status == :scheduled
    
    # Generate journey tests
    println("Running learning journey tests...")
    response = generate_learning_journey("Tunisia")
    @test response["autonomous"] == true
    @test occursin("Tunisia", response["message"])
    @test occursin("Socratic Challenge", response["message"])
    
    # Module progress tests
    println("Running module progress tests...")
    next_mod = get_next_module!(plan)
    update_module_progress!(plan, next_mod.id, 1.0f0)
    @test plan.total_progress > 0.0f0
    
    # Plan status tests
    println("Running plan status tests...")
    status = get_plan_status(plan)
    @test status["modules"]["completed"] == 1
end

println("\n" * "="^60)
println("ALL TESTS PASSED!")
println("="^60 * "\n")

# Print example response
println("Example Autonomous Response for 'Tunisia':")
println("-"^40)
response = generate_learning_journey("Tunisia")
println(response["message"])
println("-"^40)
