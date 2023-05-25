module ZipArchives

include("constants.jl")

include("reader.jl")

include("writer.jl")
export ZipWriter
export zip_newfile

end