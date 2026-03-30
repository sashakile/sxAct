# Tests for XTensor.jl — split into subfiles for modularity
using Test
using xAct

include("xtensor/test_core.jl")
include("xtensor/test_christoffel.jl")
include("xtensor/test_xtras.jl")
include("xtensor/test_identities.jl")
include("xtensor/test_sortcovds.jl")
include("xtensor/test_parser.jl")
include("xtensor/test_lowdim.jl")
