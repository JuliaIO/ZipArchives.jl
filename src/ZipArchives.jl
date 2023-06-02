module ZipArchives

include("constants.jl")
include("filename-checks.jl")

include("types.jl")

include("reader.jl")
export ZipFileReader
export ZipBufferReader
export zip_crc32
export zip_nentries
export zip_entryname
export zip_openentry

include("writer.jl")
export ZipWriter
export zip_append_archive
export zip_writefile
export zip_newfile
export zip_commitfile
export zip_abortfile

end