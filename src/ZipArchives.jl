"""
### ZipArchives

### Reading Zip archives

Archives can be read from any `AbstractVector{UInt8}` containing the data of a zip archive.

For example if you download this repo as a ".zip" from github https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip 
you can read the README in julia.

```julia
using ZipArchives
import Downloads
data = take!(Downloads.download("https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip", IOBuffer()));
archive = ZipBufferReader(data)
```

```julia
zip_names(archive)
```

```julia
zip_readentry(archive, "ZipArchives.jl-main/README.md", String) |> print
```

### Writing Zip archives

```julia
using ZipArchives, Test
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

using PrecompileTools

include("constants.jl")
include("filename-checks.jl")

include("types.jl")

include("reader.jl")
export ZipFileReader
export zip_open_filereader
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
export zip_findlast_entry
export zip_comment

export zip_test_entry
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
        r = ZipBufferReader(zipdata)
        zip_readentry(r, 1)
    end
end

end