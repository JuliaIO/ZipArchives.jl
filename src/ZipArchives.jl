module ZipArchives

include("reader.jl")

include("writer.jl")
export ZipWriter
export zip_newfile

end