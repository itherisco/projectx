"""
    ProjectXConfig.jl - Global Configuration for ProjectX/JARVIS

This module provides global settings including:
- MASTER_SEED: Fixed seed for deterministic reproducibility
- Global Xoshiro PRNG: Seeded random number generation
"""

module ProjectXConfig

using Random

# =============================================================================
# Master Seed - Fixed UInt64 for deterministic behavior
# =============================================================================

"""
    MASTER_SEED::UInt64

The master seed used to initialize the global Xoshiro PRNG.
This ensures deterministic behavior across all random operations.
"""
const MASTER_SEED::UInt64 = 0xDEADBEEF01234567

# =============================================================================
# Global Xoshiro PRNG State
# =============================================================================

"""
    global_xoshiro::Xoshiro

Global Xoshiro256** PRNG state initialized with MASTER_SEED.
All random number generation should use this instead of the default RNG.
"""
global_xoshiro::Xoshiro = Xoshiro(MASTER_SEED)

# =============================================================================
# Random Number Generation Functions
# =============================================================================

"""
    rand_xoshiro() -> Float64

Generate a random Float64 using the global Xoshiro PRNG.
Equivalent to rand() but using the seeded PRNG.
"""
function rand_xoshiro()::Float64
    return rand(global_xoshiro)
end

"""
    rand_xoshiro(::Type{Float64}) -> Float64

Generate a random Float64 using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{Float64})::Float64
    return rand(global_xoshiro, Float64)
end

"""
    rand_xoshiro(::Type{Float32}) -> Float32

Generate a random Float32 using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{Float32})::Float32
    return rand(global_xoshiro, Float32)
end

"""
    rand_xoshiro(::Type{Float16}) -> Float16

Generate a random Float16 using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{Float16})::Float16
    return rand(global_xoshiro, Float16)
end

"""
    rand_xoshiro(::Type{Int}) -> Int

Generate a random Int using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{Int})::Int
    return rand(global_xoshiro, Int)
end

"""
    rand_xoshiro(::Type{Int64}) -> Int64

Generate a random Int64 using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{Int64})::Int64
    return rand(global_xoshiro, Int64)
end

"""
    rand_xoshiro(::Type{Int32}) -> Int32

Generate a random Int32 using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{Int32})::Int32
    return rand(global_xoshiro, Int32)
end

"""
    rand_xoshiro(r::UnitRange{Int}) -> Int

Generate a random Int in the given range using the global Xoshiro PRNG.
"""
function rand_xoshiro(r::UnitRange{Int})::Int
    return rand(global_xoshiro, r)
end

"""
    rand_xoshiro(r::UnitRange{Int64}) -> Int64

Generate a random Int64 in the given range using the global Xoshiro PRNG.
"""
function rand_xoshiro(r::UnitRange{Int64})::Int64
    return rand(global_xoshiro, r)
end

"""
    rand_xoshiro(r::StepRange{Int, Int}) -> Int

Generate a random Int in the given step range using the global Xoshiro PRNG.
"""
function rand_xoshiro(r::StepRange{Int, Int})::Int
    return rand(global_xoshiro, r)
end

"""
    rand_xoshiro(A::AbstractArray) -> eltype(A)

Randomly select an element from an array using the global Xoshiro PRNG.
"""
function rand_xoshiro(A::AbstractArray)
    return rand(global_xoshiro, A)
end

"""
    rand_xoshiro(::Type{T}, dims::Dims) -> Array{T}

Generate a random array of the given type and dimensions using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{T}, dims::Dims) where T
    return rand(global_xoshiro, T, dims)
end

"""
    rand_xoshiro(::Type{T}, dims::Tuple) where T

Generate a random array of the given type and dimensions using the global Xoshiro PRNG.
"""
function rand_xoshiro(::Type{T}, dims::Tuple) where T
    return rand(global_xoshiro, T, dims)
end

"""
    rand_xoshiro(Float32, dims::Dims) -> Array{Float32}

Generate a random Float32 array with the given dimensions.
"""
function rand_xoshiro(::Type{Float32}, dims::Dims)::Array{Float32, length(dims)}
    return rand(global_xoshiro, Float32, dims)
end

"""
    rand_xoshiro(Float64, dims::Dims) -> Array{Float64}

Generate a random Float64 array with the given dimensions.
"""
function rand_xoshiro(::Type{Float64}, dims::Dims)::Array{Float64, length(dims)}
    return rand(global_xoshiro, Float64, dims)
end

# =============================================================================
# Reset Function
# =============================================================================

"""
    reset_xoshiro!()

Reset the global Xoshiro PRNG to its initial state using MASTER_SEED.
This allows for deterministic replay of random sequences.
"""
function reset_xoshiro!()
    global global_xoshiro = Xoshiro(MASTER_SEED)
    return nothing
end

# =============================================================================
# Exports
# =============================================================================

export
    MASTER_SEED,
    global_xoshiro,
    rand_xoshiro,
    reset_xoshiro!

end # module ProjectXConfig
