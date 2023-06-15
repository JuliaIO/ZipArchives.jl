module ZipArchives

include("constants.jl")
include("filename-checks.jl")

include("types.jl")

include("reader.jl")
export ZipFileReader
export ZipBufferReader

export zip_crc32

export zip_nentries
export zip_name
export zip_names
export zip_uncompressed_size
export zip_compressed_size
export zip_iscompressed
export zip_stored_crc32
export zip_definitely_utf8
export zip_isdir
export zip_isexecutablefile

export zip_test_entry
export zip_openentry
export zip_readentry

include("writer.jl")
export ZipWriter
export zip_append_archive
export zip_writefile
export zip_newfile
export zip_commitfile
export zip_abortfile
export zip_mkdir

# include("high-level.jl")

end