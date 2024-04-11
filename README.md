# ZipArchives

[![docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliahub.com/docs/General/ZipArchives/stable)
[![Build Status](https://github.com/JuliaIO/ZipArchives.jl/workflows/CI/badge.svg)](https://github.com/JuliaIO/ZipArchives.jl/actions)
[![codecov](https://codecov.io/gh/JuliaIO/ZipArchives.jl/branch/main/graph/badge.svg?token=K3J0T9BZ42)](https://codecov.io/gh/JuliaIO/ZipArchives.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Read and write Zip archives in julia.

Like Tar.jl, it is designed to use the Zip format to share data between
multiple computers, not to backup a directory and preserve all local filesystem metadata.

All public functions are exported, non exported functions and struct fields are internal.

See [test/test_simple-usage.jl](https://github.com/JuliaIO/ZipArchives.jl/blob/main/test/test_simple-usage.jl) for more examples.


### Background

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
using ZipArchives: ZipReader, zip_names, zip_readentry
using Downloads: download
data = take!(download("https://github.com/JuliaIO/ZipArchives.jl/archive/refs/heads/main.zip", IOBuffer()));
archive = ZipReader(data)
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
using ZipArchives: ZipWriter, zip_newfile
using Test: @test_throws
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


### Limitations

1. Cannot directly extract all files in an archive and write those files to disk.
1. Ignores time stamps.
1. Cannot write an archive fully in streaming mode. See https://github.com/madler/zipflow if you need this functionality.
1. Encryption and decryption not supported.
1. Only deflated and uncompressed data are supported. There is no support for bzip2 or zstd.
1. Multi disk archives not supported.
1. Cannot recover data from a corrupted archive. Especially if the end of the archive is corrupted.

## Related Packages

### [p7zip_jll](https://github.com/JuliaBinaryWrappers/p7zip_jll.jl)

p7zip_jll can create or extract many archive types including zip.
It is just a wrapper of p7zip, and must be run as an external program.

### [ZipFile](https://github.com/fhs/ZipFile.jl)

ZipFile is very similar to ZipArchives at a high level.

Currently ZipArchives has the following benefits over ZipFile:
1. Full ZIP64 support: archives larger than 4GB can be written.
2. UTF-8 file name support: entry names correctly mark that they are UTF-8.
3. Safe multi threaded reading of different entries in a single archive.
4. Files can be marked as executable. Permissions are handled like in https://github.com/JuliaIO/Tar.jl#permissions
5. By default when writing an archive, entry names are checked to avoid some common issues if the archive would be extracted on windows.
6. Ability to append to an existing zip archive, in an `IO` or in a file on disk.

ZipArchives currently has the following limitations compared to ZipFile:
1. No way to specify the modification time, times are set to 1980-01-01 00:00:00 DOS date time.
2. No `flush` function for `ZipWriter`. `close` and `zip_append_archive` can be used instead.
3. Requires at least Julia 1.6.
4. No way to read an archive from an `IOStream`, `mmap` can be used instead.




## Is there a unzip function for a whole archive?
This package cannot unzip a whole archive to disk with a single function.

This is quite complicated to do in a cross platform manner that also handles all potential errors or malicious zip archives in a safe way.

So this could be done in a separate package that depends on this package. Or using existing well tested C libraries such as `p7zip_jll`

I am happy to add other high level functions for creating zip archives to this package. 
