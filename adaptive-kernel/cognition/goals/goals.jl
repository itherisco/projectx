# cognition/goals/goals.jl - Goals submodule index

module goals

using Revise

# Include main GoalSystem
include("GoalSystem.jl")

# Re-export everything from GoalSystem
using .GoalSystem

end # module goals
