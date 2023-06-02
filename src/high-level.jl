# High level API mostly matching Tar.jl


"""
    zip_create(
        [ predicate, ] dir, [ ziparchive ];
        [ portable = true ]
    ) -> ziparchive

        predicate  :: String --> Bool
        dir        :: AbstractString
        ziparchive :: Union{AbstractString, IO}
        portable   :: Bool

Create a zip archive of the directory `dir`.

Mostly matches the syntax of `Tar.create` 
it's docstring is copied below with minor edits.

The resulting archive
is written to the path `ziparchive` or if no path is specified, a temporary path is
created and returned by the function call. If `ziparchive` is an IO object then the
zip archive content is written to that handle instead (the handle is left open).

The file will overwrite any existing file at `ziparchive` if it is a path.

Note, unlike `Tar.create`, if `ziparchive` is an IO object, it must be seekable, and should start empty.

Also, unlike `Tar.create` symlinks to directories are not followed, 
and symlinks to files are written as copies.

Lastly, unlike `Tar.create`, `basename(abspath(dir))` is used as the top level folder of the archive. 
So if there is have a "/." at the end of `dir` the contents of `dir` will be at the root of the archive.

If a `predicate` function is passed, it is called on each system path that is
encountered while recursively searching `dir` and `path` is only included in the
tarball if `predicate(path)` is true. If `predicate(path)` returns false for a
directory, then the directory is excluded entirely: nothing under that directory
will be included in the archive.

If the `portable` flag is true then path names are checked for validity on
Windows, which ensures that they don't contain illegal characters or have case insensitive name repeats. See https://stackoverflow.com/a/31976060/659248 for details.
"""
function zip_create(
        predicate::Function,
        dir::AbstractString,
        ziparchive::IO;

        portable::Bool = true,
        own_io::Bool=false,
    )
    dir_str = String(dir)
    check_create_dir(dir_str)
    dir_path = abspath(dir_str)
    zip_root = basename(dir_path)
    @argcheck zip_root != ".."
    @argcheck zip_root != "."
    
    ZipWriter(ziparchive; check_names=portable, own_io) do w
        _zip_add_dir(w, predicate, dir_str, zip_root)
    end
    ziparchive
end
function zip_create(
        predicate::Function,
        dir::AbstractString,
        ziparchive::String=tempname();
        kwargs...
    )
    open(ziparchive; write=true) do io
        zip_create(
            predicate,
            dir,
            ziparchive;
            own_io=true,
            kwargs...
        )
    end
    ziparchive
end
function zip_create(
        dir,
        ziparchive=tempname();
        kwargs...
    )
    zip_create(
        Returns(true),
        dir,
        ziparchive;
        kwargs...
    )
end

# recursive function
function _zip_add_dir(w, predicate, dirpath, zip_root)
    @argcheck !endswith(zip_root, "/")
    stuffs = readdir(dirpath)
    if isempty(stuffs) && !isempty(zip_root)
        zip_mkdir(w, zip_root*"/")
    else
        for stuff in stuffs
            stuff_path = joinpath(dirpath, stuff)
            predicate(stuff_path) || continue
            stuff_name = zip_root*"/"*stuff
            if isfile(stuff_path)
                zip_newfile(w, stuff_name;
                    executable = Sys.isexecutable(stuff_path),
                    compression_method = ZipArchives.Deflate,
                )
                open(stuff_path) do from
                    write(w, from)
                end
            elseif isdir(stuff_path) && !islink(stuff_path)
                _zip_add_dir(w, predicate, stuff_path, stuff_name)
            else
                @warn "$(stuff_path) is not a file, directory, or link to file, skipping"
            end
        end
    end
end



"""
    zip_extractall(
        [ predicate, ] ziparchive, [ dir ];
        [ set_permissions = false, ]
    ) -> dir

        predicate       :: HasEntries, Int --> Bool
        ziparchive      :: Union{AbstractString, AbstractVector{UInt8}}
        dir             :: AbstractString
        set_permissions :: Bool

Extract a zip archive located at the path `ziparchive` into the
directory `dir`. If `ziparchive` is a vector of bytes instead of a path, then the
archive contents will be read from that vector. The archive is extracted to
`dir` which must either be an existing empty directory or a non-existent path
which can be created as a new directory. If `dir` is not specified, the archive
is extracted into a temporary directory which is returned by `extract`.

If a `predicate` function is passed, it is called on each entry index that
is encountered while extracting `ziparchive` and the entry is only extracted if the
`predicate(reader, index)` is true. This can be used to selectively extract only parts of
an archive, to skip entries that cause `extract` to throw an error, or to record
what is extracted during the extraction process.

Currently symlinks are reinterpreted as regular text files, not copied or recreated.

If `set_permissions` is `false`, no permissions are set on the extracted files.
"""
function zip_extractall(
        predicate::Function,
        ziparchive::Union{AbstractString, AbstractVector{UInt8}},
        dir::Union{AbstractString, Nothing} = nothing;

        set_permissions::Bool=false,
    )
    
end












# copied from Tar.jl
check_create_dir(dir::AbstractString) =
    isdir(dir) || error("""
    `dir` not a directory: $dir
    USAGE: zip_create([predicate,] dir, [ziparchive])
    """)