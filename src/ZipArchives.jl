module ZipArchives

using PrecompileTools

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

@setup_workload begin
    # Putting some things in `@setup_workload` instead of `@compile_workload` can reduce the size of the
    # precompile file and potentially make loading faster.
    data1 = [0x01,0x04,0x08]
    data2 = codeunits("data2")
    io = IOBuffer()
    @compile_workload begin
        # all calls in this block will be precompiled, regardless of whether
        # they belong to your package or not (on Julia 1.8 and higher)
        ZipWriter(io) do w
            zip_writefile(w, "test1", data1)
            zip_writefile(w, "test2", data2)
        end
        mktemp() do path, fileio
            ZipWriter(fileio) do w
                zip_writefile(w, "test1", data1)
                zip_writefile(w, "test2", data2)
            end
        end
        zipdata = take!(io)
        r = ZipBufferReader(zipdata)
        zip_readentry(r, 1)
    end
end

end