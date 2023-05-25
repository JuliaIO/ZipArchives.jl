module ZipArchives

include("constants.jl")

include("reader.jl")
export ZipFileReader

include("writer.jl")
export ZipWriter
export zip_newfile
export zip_writefile

end