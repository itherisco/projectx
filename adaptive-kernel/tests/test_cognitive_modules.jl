"""
    Unit Tests for Cognitive System Modules

Tests for WorkingMemory, ProceduralMemory, GlobalWorkspace, Attention, 
and CognitiveArchitecture modules.
"""
module TestCognitiveModules

using Test
using Dates
using UUIDs

# Include the modules under test
include("../memory/WorkingMemory.jl")
include("../memory/ProceduralMemory.jl")
include("../cognition/GlobalWorkspace.jl")
include("../cognition/Attention.jl")
include("../cognition/CognitiveArchitecture.jl")

using ..WorkingMemory
using ..ProceduralMemory
using ..GlobalWorkspace
using ..Attention
using ..CognitiveArchitecture

# ============================================================================
# WorkingMemory Tests
# ============================================================================

@testset "WorkingMemory" begin
    @testset "Creation" begin
        wm = WorkingMemory()
        @test wm.capacity == 7
        @test wm.decay_rate == 0.1
        @test isempty(wm.buffer)
        
        wm2 = WorkingMemory(capacity=5, decay_rate=0.2)
        @test wm2.capacity == 5
        @test wm2.decay_rate == 0.2
    end
    
    @testset "Push Operations" begin
        wm = WorkingMemory()
        item1 = "test_item"
        result = push_to_working_memory!(wm, item1)
        @test result == item1
        @test length(wm.buffer) == 1
        @test wm.buffer[1]["content"] == item1
        @test wm.buffer[1]["attention"] == 1.0
    end
    
    @testset "Capacity Limit" begin
        wm = WorkingMemory(capacity=3)
        push_to_working_memory!(wm, "item1")
        push_to_working_memory!(wm, "item2")
        push_to_working_memory!(wm, "item3")
        @test length(wm.buffer) == 3
        
        # Adding a 4th item should trigger capacity management
        push_to_working_memory!(wm, "item4")
        @test length(wm.buffer) == 3  # Should not exceed capacity
    end
    
    @testset "Pop Operations" begin
        wm = WorkingMemory()
        push_to_working_memory!(wm, "item1")
        push_to_working_memory!(wm, "item2")
        
        popped = pop_from_working_memory(wm)
        @test popped == "item2"
        @test length(wm.buffer) == 1
        
        # Pop from empty buffer
        wm_empty = WorkingMemory()
        result = pop_from_working_memory(wm_empty)
        @test result === nothing
    end
    
    @testset "Decay Operations" begin
        wm = WorkingMemory(decay_rate=0.5)
        push_to_working_memory!(wm, "item1")
        initial_attention = wm.buffer[1]["attention"]
        
        # Simulate time passing by manually setting timestamp
        wm.buffer[1]["timestamp"] = now() - Second(10)
        
        decay_working_memory!(wm)
        @test wm.buffer[1]["attention"] < initial_attention
    end
    
    @testset "Clear Operations" begin
        wm = WorkingMemory()
        push_to_working_memory!(wm, "item1")
        push_to_working_memory!(wm, "item2")
        
        clear_working_memory!(wm)
        @test isempty(wm.buffer)
    end
    
    @testset "Attention Weights" begin
        wm = WorkingMemory()
        push_to_working_memory!(wm, "item1")
        
        weights = calculate_attention_weights(wm)
        @test length(weights) == 1
        @test weights[1] > 0
        
        attended = get_attended_items(wm)
        @test length(attended) >= 0
    end
end

# ============================================================================
# ProceduralMemory Tests
# ============================================================================

@testset "ProceduralMemory" begin
    @testset "Creation" begin
        pm = ProceduralMemory()
        @test isempty(pm.procedures)
        @test pm.max_history == 20
        @test pm.decay_rate == 0.05
    end
    
    @testset "Create Procedure" begin
        pm = ProceduralMemory()
        proc = create_procedure!(pm, "test_capability", "test_procedure"; 
            parameters=Dict("key" => "value"))
        
        @test proc.name == "test_procedure"
        @test proc.capability_id == "test_capability"
        @test proc.success_rate == 0.5  # Default initial success rate
        @test proc.times_executed == 0
    end
    
    @testset "Record Execution" begin
        pm = ProceduralMemory()
        proc = create_procedure!(pm, "cap1", "proc1")
        
        record_execution!(pm, proc.id, success=true, execution_time=1.0)
        @test proc.times_executed == 1
        @test proc.success_rate > 0.5
        
        record_execution!(pm, proc.id, success=false, execution_time=2.0)
        @test proc.times_executed == 2
    end
    
    @testset "Get Best Procedure" begin
        pm = ProceduralMemory()
        proc1 = create_procedure!(pm, "cap1", "proc1")
        proc2 = create_procedure!(pm, "cap1", "proc2")
        
        # Make proc2 more successful
        record_execution!(pm, proc2.id, success=true, execution_time=1.0)
        record_execution!(pm, proc2.id, success=true, execution_time=1.0)
        
        best = get_best_procedure(pm, "cap1")
        @test best !== nothing
        @test best.id == proc2.id
    end
    
    @testset "Get Procedures by Capability" begin
        pm = ProceduralMemory()
        create_procedure!(pm, "cap_a", "proc1")
        create_procedure!(pm, "cap_a", "proc2")
        create_procedure!(pm, "cap_b", "proc3")
        
        procs_a = get_procedures_by_capability(pm, "cap_a")
        @test length(procs_a) == 2
        
        procs_b = get_procedures_by_capability(pm, "cap_b")
        @test length(procs_b) == 1
    end
end

# ============================================================================
# GlobalWorkspace Tests
# ============================================================================

@testset "GlobalWorkspace" begin
    @testset "Creation" begin
        gw = create_workspace()
        @test isempty(gw.subscribers)
        @test gw.current_content === nothing
    end
    
    @testset "Subscribe/Unsubscribe" begin
        gw = create_workspace()
        
        sub = subscribe!(gw, "TestModule"; priority=PRIORITY_NORMAL)
        @test sub.name == "TestModule"
        @test length(gw.subscribers) == 1
        
        unsubscribe!(gw, "TestModule")
        @test isempty(gw.subscribers)
    end
    
    @testset "Broadcast Content" begin
        gw = create_workspace()
        subscribe!(gw, "Module1"; priority=PRIORITY_NORMAL)
        
        result = broadcast_content(gw, "test_content", "Module1"; importance=0.8)
        @test result.success == true
        @test gw.current_content !== nothing
    end
    
    @testset "Competition" begin
        gw = create_workspace()
        subscribe!(gw, "Module1"; priority=PRIORITY_LOW)
        subscribe!(gw, "Module2"; priority=PRIORITY_HIGH)
        
        add_competing_content!(gw, "content1", "Module1"; importance=0.3)
        add_competing_content!(gw, "content2", "Module2"; importance=0.9)
        
        winner = compete_for_consciousness(gw)
        @test winner !== nothing
    end
    
    @testset "Clear Workspace" begin
        gw = create_workspace()
        subscribe!(gw, "Module1")
        broadcast_content(gw, "test", "Module1")
        
        clear_workspace(gw)
        @test gw.current_content === nothing
    end
end

# ============================================================================
# Attention Tests
# ============================================================================

@testset "Attention" begin
    @testset "Creation" begin
        att = create_attention_system()
        @test att.attention_budget == 1.0
        @test att.alerting_level == 0.8
    end
    
    @testset "Allocate Attention" begin
        att = create_attention_system()
        item = allocate_attention!(att, "test_item"; priority=PRIORITY_HIGH)
        @test item.content == "test_item"
        @test item.priority == PRIORITY_HIGH
    end
    
    @testset "Shift Attention" begin
        att = create_attention_system()
        item1 = allocate_attention!(att, "item1"; priority=PRIORITY_NORMAL)
        item2 = allocate_attention!(att, "item2"; priority=PRIORITY_HIGH)
        
        shift_attention!(att, item2)
        @test att.current_focus == item2
    end
    
    @testset "Attentional Demand" begin
        att = create_attention_system()
        add_attention_demand!(att, "task1"; priority=PRIORITY_NORMAL)
        add_attention_demand!(att, "task2"; priority=PRIORITY_HIGH)
        
        demand = calculate_attentional_demand(att)
        @test demand > 0
    end
    
    @testset "Suppress Distraction" begin
        att = create_attention_system()
        item = allocate_attention!(att, "distraction"; priority=PRIORITY_LOW)
        
        suppressed = suppress_distraction!(att, item)
        @test suppressed == true
    end
    
    @testset "Release Attention" begin
        att = create_attention_system()
        item = allocate_attention!(att, "item")
        
        release_attention!(att, item)
        @test !in(item, att.demands)
    end
end

# ============================================================================
# CognitiveArchitecture Integration Tests
# ============================================================================

@testset "CognitiveArchitecture" begin
    @testset "Creation" begin
        arch = create_cognitive_architecture()
        @test arch !== nothing
        @test arch.cycle_state.phase == PHASE_REST
    end
    
    @testset "Perceive Phase" begin
        arch = create_cognitive_architecture()
        result = perceive(arch, "test_input")
        @test result == "test_input"
        @test arch.cycle_state.phase == PHASE_OBSERVE
    end
    
    @testset "Full Cognitive Cycle" begin
        arch = create_cognitive_architecture()
        
        # Subscribe a module to the workspace
        GlobalWorkspace.subscribe!(arch.global_workspace, "TestModule")
        
        # Run a full cycle
        result = full_cognitive_cycle(arch, "test_input")
        @test arch.cycle_state.cycle_count == 1
    end
    
    @testset "Reset Architecture" begin
        arch = create_cognitive_architecture()
        push_to_working_memory!(arch.working_memory, "item1")
        
        reset_architecture!(arch)
        @test isempty(arch.working_memory.buffer)
    end
    
    @testset "Architecture Status" begin
        arch = create_cognitive_architecture()
        status = get_architecture_status(arch)
        
        @test haskey(status, "id")
        @test haskey(status, "working_memory")
        @test haskey(status, "attention")
        @test haskey(status, "workspace")
    end
    
    @testset "Learn Procedure" begin
        arch = create_cognitive_architecture()
        
        learn_procedure(arch, "cap1", "proc1")
        procs = retrieve_procedures(arch, "cap1")
        
        @test length(procs) >= 1
    end
end

# ============================================================================
# Run all tests
# ============================================================================

end  # module TestCognitiveModules
