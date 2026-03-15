# setup_environment.jl
# This script ensures all dependencies for ProjectX are installed and precompiled.

using Pkg

# List of required dependencies
deps = [
    "Flux",
    "Distributions",
    "Functors"
]

# Add each dependency
for dep in deps
    println("Adding dependency: $dep")
    Pkg.add(dep)
end

println("All dependencies are installed and ready.")