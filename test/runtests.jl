using Test
using Random
using ZipArchives

Random.seed!(1234)



@test Any[] == detect_ambiguities(Base, Core, ZipArchives)
include("test_simple-usage.jl")
include("test_writer.jl")

