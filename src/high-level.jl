# High level API

# This is commented out because of strange behavior on windows.
# It is probably better to use 
# https://github.com/JuliaBinaryWrappers/p7zip_jll.jl 
# for high level operations for now.

# """
#     zip_add_path(
#         w::ZipWriter,
#         path::AbstractString,
#         zip_prefix::AbstractString = "",
#         ;
#         predicate = Returns(true),
#     )::Nothing

# Add a file from a path, or add a directory and its contents recursively.

# Do not follow symlinks to directories.

# Write symlinks to files as copies.

# `zip_prefix` is prepended to all entry names.

# Only write an entry if `predicate` called on `path` or a subpath of `path` returns true.
# If `path` or a subpath of `path` is a directory, only recurse into its contents if `predicate(subpath)` is true.
# """
# function zip_add_path(
#         w::ZipWriter,
#         path::AbstractString,
#         zip_prefix::AbstractString = "",
#         ;
#         predicate = Returns(true),
#     )::Nothing
#     _zip_add_path(w, String(path), String(zip_prefix), predicate)
# end

# # recursive function
# function _zip_add_path(
#         w::ZipWriter,
#         stuff_path::String,
#         zip_prefix::String,
#         predicate,
#     )::Nothing
#     predicate(stuff_path) || return
#     if isfile(stuff_path)
#         stuff_name = zip_prefix*basename(stuff_path)
#         zip_newfile(w, stuff_name;
#             # Note, on windows this tends to make everything executable.
#             executable = Sys.isexecutable(stuff_path),
#             compress = true,
#         )
#         open(stuff_path) do from
#             write(w, from)
#         end
#         zip_commitfile(w)
#     elseif isdir(stuff_path) && !islink(stuff_path)
#         bdname = basename(dirname(joinpath(abspath(stuff_path),"")))
#         stuffs = readdir(stuff_path)
#         if isempty(stuffs) && !isempty(bdname)
#             zip_mkdir(w, zip_prefix*bdname*"/")
#         else
#             for stuff in stuffs
#                 _zip_add_path(w, predicate, joinpath(stuff_path, stuff), zip_prefix*bdname*"/")
#             end
#         end
#     else
#         @warn "$(stuff_path) is not a file, directory, or link to file, skipping"
#     end
#     return
# end