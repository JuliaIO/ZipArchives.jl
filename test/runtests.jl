using Test
using Random
using ZipArchives

Random.seed!(1234)



# @test Any[] == detect_ambiguities(Base, Core, ZipArchives)
include("test_simple-usage.jl")
include("test_writer.jl")
include("test_reader.jl")
include("test_appending.jl")
include("test_ported-go-tests.jl")
# include("test_big_zips.jl")
