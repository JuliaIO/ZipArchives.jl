# ZipArchives (WIP)

[![Build Status](https://github.com/medyan-dev/ZipArchives.jl/workflows/CI/badge.svg)](https://github.com/medyan-dev/ZipArchives.jl/actions)
[![codecov](https://codecov.io/gh/medyan-dev/ZipArchives.jl/branch/main/graph/badge.svg?token=K3J0T9BZ42)](https://codecov.io/gh/medyan-dev/ZipArchives.jl)

This package is not well tested yet.

Read and write Zip archives in julia.

See [test/test_simple-usage.jl](test/test_simple-usage.jl) for examples.

All public functions are exported, non exported functions and struct fields are internal.


### Terminology

#### Archive
The actual `.zip` file on disk or in a buffer in memory.

#### Entry
A file or empty directory stored in an archive. 

### Limitations

1. Cannot directly extract all files in an archive and write those files to disk.
1. Ignores time stamps.
1. Cannot write an archive fully in streaming mode. See https://github.com/madler/zipflow if you need this functionality.
1. Encryption and decryption not supported.
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
5. By default when writing an achive entry names are checked to avoid some common issues if the archive would be extracted on windows.
6. Ability to append to an existing zip archive, in an `IO` or in a file on disk.

ZipArchives currently has the following limitations compared to ZipFile:
1. No way to specify the modification time, times are set to zero dos time.
2. No `flush` function for `ZipWriter`. `close` and `zip_append_archive` can be used instead.
3. Requires at least Julia 1.6.
4. Not as well tested.




## Is there a unzip function for a whole archive?
This package cannot unzip a whole archive to disk with a single function.

This is quite complicated to do in a cross platform manner that also handles all potential errors or malicious zip archives in a safe way.

So this could be done in a seperate package that depends on this package. Or using existing well tested C libraries such as `p7zip_jll`

I am happy to add other high level functions for creating zip archives to this package. 
