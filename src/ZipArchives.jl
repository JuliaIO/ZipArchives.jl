module ZipArchives

include("constants.jl")

include("reader.jl")
export ZipFileReader
export zip_nentries
export zip_entryname

include("writer.jl")
export ZipWriter
export zip_newfile
export zip_writefile

end