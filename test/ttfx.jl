using Pkg.Artifacts
using ZipArchives

r = ZipBufferReader(read(joinpath(artifact"fixture", "fixture", "ubuntu22-7zip.zip")))
println(length(zip_names(r)))
println(length(zip_readentry(r, "ZipArchives.jl", String)))
println(length(zip_readentry(r, 1, String)))