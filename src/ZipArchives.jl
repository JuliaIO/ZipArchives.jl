"""
### ZipArchives

An archive contains a list of named entries. 
These entries represent archived files or empty directories.
Internally there is no file system like tree structure; however,
the entry name may have "/"s to represented a relative path.

At the end of the archive there is a "central directory" of all entry names, sizes,
and other metadata.

The central directory gets parsed first when reading an archive.

The central directory makes it fast to read just one random entry out of a very large archive.

When writing it is important to close the writer so the central directory gets written out.

### Reading Zip archives

Archives can be read from any `AbstractVector{UInt8}` containing the data of a zip archive.

For example if you download this repo as a ".zip" from github https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip you can read this README in julia.

```julia
using ZipArchives
import Downloads
data = take!(Downloads.download("https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip", IOBuffer()));
archive = ZipBufferReader(data)
```

Check the names in the archive.
```julia
zip_names(archive)
```

Print this README file.
```julia
zip_readentry(archive, "ZipArchives.jl-main/README.md", String) |> print
```

### Writing Zip archives

```julia
using ZipArchives, Test
filename = tempname()
```
Open a new zip file with `ZipWriter`
If a file already exists at filename, it will be replaced.
Using the do syntax ensures the file will be closed.
Otherwise make sure to close the ZipWriter to finish writing the file.

```julia
ZipWriter(filename) do w
    # Write data to "test/test1.txt" inside the zip archive.
    # Always use a / as a path separator even on windows.
    @test_throws ArgumentError zip_newfile(w, "test\\test1.txt")
    # `zip_newfile` turns w into an IO that represents a file in the archive.
    zip_newfile(w, "test/test1.txt")
    write(w, "I am data inside test1.txt in the zip file")

    # Write an empty file.
    # After calling `newfile` there is no direct way to edit any previous files in the archive.
    zip_newfile(w, "test/empty.txt")

    # Write data to "test2.txt" inside the zip file.
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