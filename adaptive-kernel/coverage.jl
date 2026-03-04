#!/usr/bin/env julia
# coverage.jl - Code coverage analysis for Adaptive Kernel
# Provides coverage metrics for CI/CD integration

import Pkg
using Coverage
using JSON
using Dates

# Ensure we're in the right environment
Pkg.activate(@__DIR__)

function analyze_coverage()
    println("========================================")
    println("CODE COVERAGE ANALYSIS")
    println("========================================")
    println("Started: $(now())")
    println("")
    
    # Get source files
    source_dirs = ["cognition", "kernel", "memory", "planning", "persistence", 
                   "resilience", "sandbox", "sensory", "brain", "capabilities"]
    
    all_files = String[]
    for dir in source_dirs
        path = joinpath(@__DIR__, dir)
        if isdir(path)
            for (root, dirs, files) in walkdir(path)
                for file in files
                    if endswith(file, ".jl")
                        push!(all_files, joinpath(root, file))
                    end
                end
            end
        end
    end
    
    println("Source files analyzed: $(length(all_files))")
    
    # Process coverage data
    coverage_data = Coverage.process_folder(@__DIR__)
    
    if isempty(coverage_data)
        println("⚠ No coverage data found")
        
        # Save empty results
        results = Dict(
            "timestamp" => string(now()),
            "covered_lines" => 0,
            "total_lines" => 0,
            "coverage_percentage" => 0.0,
            "files_analyzed" => 0,
            "status" => "no_data"
        )
        
        open(joinpath(@__DIR__, "coverage_results.json"), "w") do f
            JSON.print(f, results, 2)
        end
        
        return results
    end
    
    # Calculate coverage
    covered_lines = count(coverage_data)
    total_lines = length(coverage_data)
    coverage_pct = total_lines > 0 ? (covered_lines / total_lines) * 100 : 0.0
    
    println("")
    println("--- Coverage Results ---")
    println("Covered lines: $covered_lines")
    println("Total lines: $total_lines")
    println("Coverage: $(round(coverage_pct, digits=2))%")
    println("")
    
    # Per-file coverage
    file_coverage = Dict{String, Any}()
    for (file, lines) in coverage_data
        covered = count(lines)
        total = length(lines)
        pct = total > 0 ? (covered / total) * 100 : 0.0
        file_coverage[file] = Dict(
            "covered" => covered,
            "total" => total,
            "percentage" => round(pct, digits=2)
        )
    end
    
    # Sort by coverage percentage
    sorted_files = sort(collect(file_coverage), by = x -> x[2]["percentage"])
    
    println("--- Per-File Coverage ---")
    for (file, cov) in sorted_files
        println("  $(cov["percentage"])% - $(basename(file)) ($(cov["covered"])/$(cov["total"]))")
    end
    
    # Save results
    results = Dict(
        "timestamp" => string(now()),
        "covered_lines" => covered_lines,
        "total_lines" => total_lines,
        "coverage_percentage" => round(coverage_pct, digits=2),
        "files_analyzed" => length(coverage_data),
        "status" => "complete",
        "per_file" => file_coverage
    )
    
    open(joinpath(@__DIR__, "coverage_results.json"), "w") do f
        JSON.print(f, results, 2)
    end
    
    # Save text summary
    open(joinpath(@__DIR__, "coverage_results.txt"), "w") do f
        write(f, "Code Coverage Results\n")
        write(f, "=====================\n")
        write(f, "Timestamp: $(now())\n")
        write(f, "Covered Lines: $covered_lines\n")
        write(f, "Total Lines: $total_lines\n")
        write(f, "Coverage: $(round(coverage_pct, digits=2))%\n")
        write(f, "Files Analyzed: $(length(coverage_data))\n")
        write(f, "\nPer-File Coverage:\n")
        write(f, "-----------------\n")
        for (file, cov) in sorted_files
            write(f, "$(cov["percentage"])% - $(basename(file)) ($(cov["covered"])/$(cov["total"]))\n")
        end
    end
    
    println("")
    println("✓ Coverage results saved to:")
    println("  - coverage_results.json")
    println("  - coverage_results.txt")
    println("========================================")
    
    return results
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__()
    analyze_coverage()
end
