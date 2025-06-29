using Random: Random
using ZipArchives: ZipArchives
using Aqua: Aqua

Aqua.test_all(ZipArchives)

Random.seed!(1234)



# @test Any[] == detect_ambiguities(Base, Core, ZipArchives)
include("test_bytes2string.jl")
include("test_simple-usage.jl")
include("test_file-array.jl")
include("test_filename-checks.jl")
include("test_show.jl")
include("test_writer.jl")
include("test_reader.jl")
include("test_appending.jl")
include("test_ported-go-tests.jl")
include("test_big_zips.jl")