using Pkg.Artifacts: @artifact_str
using ZipArchives: ZipBufferReader, zip_names, zip_readentry

r = ZipBufferReader(read(joinpath(artifact"fixture", "fixture", "ubuntu22-7zip.zip")))
println(length(zip_names(r)))
println(length(zip_readentry(r, "ZipArchives.jl", String)))
println(length(zip_readentry(r, 1, String)))