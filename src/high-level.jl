# High level API


"""
    zip_add_path(
        w::ZipWriter,
        path::AbstractString,
        zip_prefix::AbstractString = "",
        ;
        predicate = Returns(true),
    )::Nothing

Add a file from a path, or add a directory and its contents recursively.

Do not follow symlinks to directories.

Write symlinks to files as copies.

`zip_prefix` is appended to all entry names.

Only write an entry if `predicate` called on `path` or a subpath of `path` returns true.
If `path` or a subpath of `path` is a directory, only recurse into its contents if `predicate(subpath)` is true.
"""
function zip_add_path(
        w::ZipWriter,
        path::AbstractString,
        zip_prefix::AbstractString = "",
        ;
        predicate = Returns(true),
    )::Nothing
    _zip_add_path(w, String(path), String(zip_prefix), predicate)
end

# recursive function
function _zip_add_path(
        w::ZipWriter,
        stuff_path::String,
        zip_prefix::String,
        predicate,
    )::Nothing
    predicate(stuff_path) || return
    if isfile(stuff_path)
        stuff_name = zip_prefix*basename(stuff_path)
        zip_newfile(w, stuff_name;
            executable = Sys.isexecutable(stuff_path),
            compression_method = ZipArchives.Deflate,
        )
        open(stuff_path) do from
            write(w, from)
        end
        zip_commitfile(w)
    elseif isdir(stuff_path) && !islink(stuff_path)
        bdname = basename(dirname(joinpath(abspath(stuff_path),"")))
        stuffs = readdir(stuff_path)
        if isempty(stuffs) && !isempty(bdname)
            zip_mkdir(w, zip_prefix*bdname*"/")
        else
            for stuff in stuffs
                _zip_add_path(w, predicate, joinpath(stuff_path, stuff), zip_prefix*bdname*"/")
            end
        end
    else
        @warn "$(stuff_path) is not a file, directory, or link to file, skipping"
    end
    return
end



"""
    zip_extractall(
        [ predicate, ] zipreader, [ dir ];
        [ set_permissions = false, ]
    ) -> dir

        predicate       :: HasEntries, Int --> Bool
        zipreader      :: Union{ZipBufferReader, ZipFileReader}
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
        zipreader::Union{ZipBufferReader, ZipFileReader},
        dir::Union{AbstractString, Nothing} = nothing;

        set_permissions::Bool=false,
    )
    
end

function zip_extract_entry()