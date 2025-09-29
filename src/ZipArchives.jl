"""
### ZipArchives

### Reading Zip archives

Archives can be read from any `AbstractVector{UInt8}` containing the data of a zip archive.

For example if you download this repo as a ".zip" from github https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip 
you can read the README in julia.

```julia
using ZipArchives: ZipReader, zip_names, zip_readentry
using Downloads: download
data = take!(download("https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip", IOBuffer()));
archive = ZipReader(data)
```

```julia
zip_names(archive)
```

```julia
zip_readentry(archive, "ZipArchives.jl-main/README.md", String) |> print
```

### Writing Zip archives

```julia
using ZipArchives: ZipWriter, zip_newfile
using Test: @test_throws
filename = tempname()
```

```julia
ZipWriter(filename) do w
    @test_throws ArgumentError zip_newfile(w, "test\\test1.txt")
    zip_newfile(w, "test/test1.txt")
    write(w, "I am data inside test1.txt in the zip file")

    zip_newfile(w, "test/empty.txt")

    zip_newfile(w, "test/test2.txt")
    write(w, "I am data inside test2.txt in the zip file")
end
```
"""
module ZipArchives

using CodecZlib: DeflateCompressorStream, DeflateDecompressorStream, DeflateCompressor
using CodecInflate64: Deflate64DecompressorStream
using TranscodingStreams: TranscodingStreams, TranscodingStream, Noop, NoopStream
using ArgCheck: @argcheck
using Zlib_jll: Zlib_jll
using InputBuffers: InputBuffer
using PrecompileTools: @setup_workload, @compile_workload

include("constants.jl")
include("filename-checks.jl")

include("types.jl")

include("reader.jl")
export ZipReader
export ZipBufferReader # alias for ZipReader for compat reasons

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
export zip_findlast_entry
export zip_comment
export zip_compression_method
export zip_general_purpose_bit_flag
export zip_entry_data_offset

export zip_test_entry
export zip_test
export zip_openentry
export zip_readentry

include("writer.jl")
export ZipWriter
export zip_append_archive
export zip_writefile
export zip_newfile
export zip_name_collision
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
        r = ZipReader(zipdata)
        zip_readentry(r, 1)
    end
end

end