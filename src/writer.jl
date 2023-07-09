using ArgCheck
using CodecZlib
using TranscodingStreams


"""
    mutable struct ZipWriter{S<:IO} <: IO
    ZipWriter(io::IO; zip_kwargs...)::ZipWriter{typeof(io)}
    ZipWriter(f::Function, io::IO; zip_kwargs...)::ZipWriter{typeof(io)}

Create a zip archive writer on `io`.

These methods also work with a `filename::AbstractString` instead of an `io::IO`.
In that case, the passed keyword arguments will be used for `Base.open`.

`io` must not be modified before the `ZipWriter` is closed (except using the wrapping `ZipWriter`).

The `ZipWriter` becomes a writable `IO` after a call to [`zip_newfile`](@ref)

    zip_newfile(w::ZipWriter, name::AbstractString; newfile_kwargs...)

Any writes to the `ZipWriter` will write to the last specified new file.

If [`zip_newfile`](@ref) is called while `ZipWriter` is writable, the previous file is committed to the archive. There is no way to edit previously written data.

An alternative to [`zip_newfile`](@ref) is [`zip_writefile`](@ref)

    zip_writefile(w::ZipWriter, name::AbstractString, data::AbstractVector{UInt8})

This will directly write a vector of data to a file entry in `w`.
Unlike [`zip_newfile`](@ref) using [`zip_writefile`](@ref) doesn't require the wrapped `io` to be seekable.


`Base.close` on a `ZipWriter` will only close the wrapped `io` if `zip_kwargs` has `own_io=true` or the `ZipWriter` was created from a filename.

# Multi threading

A single `ZipWriter` instance doesn't allow mutations or 
writes from multiple threads at the same time.

Use locks if you want this.

# Appending

The archive will start writing at the current position of `io`, so if `io`
is from an existing file opened with append, the archive will be appended as well.

This is fine because zip archives can have arbitrary data at the start. 
That data should be ignored by a zip reader.

If you want to add entries to existing zip archive, use [`zip_append_archive`](@ref)

# Optional Keywords
- `check_names::Bool=true`: Best attempt to error if new entry names aren't valid on windows 
or already exist in the archive in a case insensitive way.
"""
function ZipWriter(f::Function, io::IO; zip_kwargs...)
    w = ZipWriter(io; zip_kwargs...)
    try
        f(w)
    finally
        close(w)
    end
    w
end
function ZipWriter(filename::AbstractString; open_kwargs...)
    ZipWriter(Base.open(filename; write=true, open_kwargs...); own_io=true)
end
function ZipWriter(f::Function, filename::AbstractString; open_kwargs...)
    ZipWriter(f, Base.open(filename; write=true, open_kwargs...); own_io=true)
end

function Base.show(io::IO, w::ZipWriter)
    print(io, "ZipArchives.ZipWriter(")
    show(io, w._io)
    print(io, ")")
end


"""
    zip_append_archive(io::IO; trunc_footer=true, zip_kwargs=(;))::ZipWriter

Return a `ZipWriter` that will add entries to the existing zip archive in `io`.

These functions also work with a `filename::AbstractString` instead of an `io::IO`.
In that case, the passed keyword arguments will be used for `Base.open`.

If `io` doesn't have a valid zip archive footer already, this function will error.

If `trunc_footer=true` the no longer needed zip archive footer at the end of `io` will be truncated.
Otherwise, it will be left as is.
"""
function zip_append_archive(io::IO; trunc_footer=true, zip_kwargs=(;))::ZipWriter
    try
        entries, central_dir_buffer, central_dir_offset = parse_central_directory(io)
        if trunc_footer
            truncate(io, central_dir_offset)
        end
        seekend(io)
        w = ZipWriter(io; zip_kwargs...)
        w.entries = entries
        w.central_dir_buffer = central_dir_buffer
        if w.check_names
            w.used_names_lower = Set{String}(norm_name(String(view(central_dir_buffer, e.name_range))) for e in entries)
        end
        w
    catch # close io if there is an error parsing entries
        if get(zip_kwargs, :own_io, false)
            close(io)
        end
        rethrow()
    end
end
function zip_append_archive(f::Function, io::IO; kwargs...)::ZipWriter
    w = zip_append_archive(io; kwargs...)
    try
        f(w)
    finally
        close(w)
    end
    w
end
function zip_append_archive(filename::AbstractString; open_kwargs...)
    zip_append_archive(
        Base.open(filename; read=true, write=true, open_kwargs...);
        zip_kwargs=(;own_io=true)
    )
end
function zip_append_archive(f::Function, filename::AbstractString; open_kwargs...)
    zip_append_archive(
        f,
        Base.open(filename; read=true, write=true, open_kwargs...);
        zip_kwargs=(;own_io=true)
    )
end

Base.isopen(w::ZipWriter) = !w.closed

Base.isreadable(::ZipWriter) = false

Base.iswritable(w::ZipWriter) = !isnothing(w.partial_entry)

"""
    zip_newfile(w::ZipWriter, name::AbstractString; 
        compression_method=Store,
    )

Start a new file entry named `name`.

This will commit any currently open entry 
and make `w` writable for file entry `name`.

The wrapped `IO` in `w` must be seekable to use this function.
If not see [`zip_writefile`](@ref)

# Optional Keywords
- `compress::Bool=false`: 
If false no compression is used and other compression options are ignored.
- `compression_level::Int=-1`:
1 is fastest, 9 is smallest file size. 
0 is no compression, and -1 is a good compromise between speed and file size.
- `compression_method=Deflate`: Currently only `Deflate` and `Store` are supported.
- `executable::Union{Nothing,Bool}=nothing`: Set to true to mark file as executable.
Defaults to false.
- `external_attrs::Union{Nothing,UInt32}=nothing`: Manually override the 
external file attributes: See https://unix.stackexchange.com/questions/14705/the-zip-formats-external-file-attribute
"""
function zip_newfile(w::ZipWriter, name::AbstractString; 
        compress::Bool=false,
        compression_method::UInt16=Deflate,
        compression_level::Int=-1,
        executable::Union{Nothing,Bool}=nothing,
        external_attrs::Union{Nothing,UInt32}=nothing,
    )
    @argcheck isopen(w)
    zip_commitfile(w)
    namestr::String = String(name)
    @argcheck ncodeunits(namestr) ≤ typemax(UInt16)
    normed_name = nothing
    if w.check_names
        basic_name_check(namestr)
        @argcheck !isnothing(external_attrs) || !endswith(namestr, "/")
        normed_name = norm_name(namestr)
        @argcheck normed_name ∉ w.used_names_lower
    end
    @assert !iswritable(w)
    io = w._io
    pe = PartialEntry(;
        name=namestr,
        normed_name,
        w.force_zip64,
        offset=0, # place holder offset
    )

    if !isnothing(executable) && executable
        pe.external_attrs = UInt32(0o0100755)<<16
    end
    # Manual override of external_attrs
    if !isnothing(external_attrs)
        pe.external_attrs = external_attrs
    end

    # If compress is false ignore other compression options
    real_compression_method = if compress
        compression_method
    else
        Store
    end
    codec, level_bits = if real_compression_method==Store
        (Noop(), UInt16(0))
    elseif real_compression_method==Deflate
        @argcheck compression_level ∈ (-1:9)
        (
            DeflateCompressor(;level = compression_level),
            deflate_level_bits(compression_level),
        )
    else
        throw(ArgumentError("compression_method must be Deflate or Store"))
    end
    pe.bit_flags |= level_bits
    w.transcoder = TranscodingStream(codec, io; sharedbuf=false)
    pe.method = real_compression_method
    
    write_local_header(io, pe)
    # sometimes position before a write is the read position.
    # That is why I am getting the offset after the write.
    pe.offset = position(io) - pe.local_header_size
    w.partial_entry = pe
    @assert iswritable(w)
    nothing
end

"""
Write little endian Integer or String or bytes to a buffer.
"""
function write_buffer(b::Vector{UInt8}, p::Int, x::Integer)::Int
    for i in 1:sizeof(x)
        b[p] = x%UInt8
        x >>= 8
        p += 1
    end
    sizeof(x)
end
function write_buffer(b::Vector{UInt8}, p::Int, x::AbstractVector{UInt8})::Int
    copyto!(b, p, x, firstindex(x), length(x))
    # b[p:p+length(x)-1] .= x
    length(x)
end
function write_buffer(b::Vector{UInt8}, p::Int, x::String)::Int
    nb = ncodeunits(x)
    data = codeunits(x)
    for i in eachindex(data)
        b[p+i-1] = data[i]
    end
    nb
    # write_buffer(b, p, codeunits(x))
end



function assert_writeable(w::ZipWriter)
    if !iswritable(w)
        if isopen(w)
            throw(ArgumentError("ZipWriter not writable, call zip_newfile first"))
        else
            throw(ArgumentError("ZipWriter is closed"))
        end
    end
end

Base.write(w::ZipWriter, x::UInt8) = write(w, Ref(x))

function Base.unsafe_write(w::ZipWriter, p::Ptr{UInt8}, n::UInt)::Int
    iszero(n) && return 0
    (n > typemax(Int)) && throw(ArgumentError("too many bytes. Tried to write $n bytes"))
    assert_writeable(w)
    pe = something(w.partial_entry)
    nb::UInt = unsafe_write(something(w.transcoder), p, n)
    pe.crc32 = unsafe_crc32(p, nb, pe.crc32)
    pe.uncompressed_size += nb
    # pe.entry.compressed_size is updated in zip_commitfile
    nb
end

function Base.position(w::ZipWriter)::Int64
    assert_writeable(w)
    something(w.partial_entry).uncompressed_size
end

"""
    zip_commitfile(w::ZipWriter)
Close any open entry making `w` not writable.
If there is some error, this will behave like [`zip_abortfile`](@ref)
then rethrow the error.
"""
function zip_commitfile(w::ZipWriter)
    if iswritable(w)
        pe = something(w.partial_entry)
        transcoder = something(w.transcoder)
        w.transcoder = nothing
        w.partial_entry = nothing
        # If some error happens, the file will be partially written,
        # but not included in the central directory.
        # Finish the compressing here, but don't close underlying IO.
        try
            write(transcoder, TranscodingStreams.TOKEN_END)
        finally
            # Prevent memory leak maybe.
            TranscodingStreams.finalize(transcoder.codec)
        end
        cur_offset = position(w._io)
        pe.compressed_size = cur_offset - pe.offset - pe.local_header_size

        # note, make sure never to change the partial_entry without increasing these
        if !iszero(pe.uncompressed_size) | !iszero(pe.compressed_size)
            # Must go back and update the local header if any data was written.
            # TODO add better error message about requiring seekable IO if this fails
            try
                seek(w._io, pe.offset)
                write_local_header(w._io, pe)
                after_write_offset = position(w._io)
                cur_offset = max(cur_offset, after_write_offset)
                # sometimes seek changes the read position
                # but the write position is forced to the end on the next write.
                # that is what the max is here to handle.
                @argcheck after_write_offset == pe.offset + pe.local_header_size
            finally
                seek(w._io, cur_offset)
            end
        end
        entry = append_entry!(w.central_dir_buffer, pe)
        if w.check_names
            push!(w.used_names_lower, something(pe.normed_name))
        end
        push!(w.entries, entry)
    end
    nothing
end

"""
    zip_abortfile(w::ZipWriter)
Close any open entry making `w` not writable.

The open entry is not added to the list of entries 
so will be ignored when the zip archive is read.
"""
function zip_abortfile(w::ZipWriter)
    if iswritable(w)
        transcoder = something(w.transcoder)
        w.transcoder = nothing
        w.partial_entry = nothing
        # Finish the compressing here, but don't close underlying IO.
        try
            write(transcoder, TranscodingStreams.TOKEN_END)
        finally
            # Prevent memory leak maybe.
            TranscodingStreams.finalize(transcoder.codec)
        end
    end
    nothing
end

"""
    zip_writefile(w::ZipWriter, name::AbstractString, data::AbstractVector{UInt8})

Write data as a file entry named `name`.

Unlike zip_newfile, the wrapped IO doesn't need to be seekable.
`w` isn't writable after. The written data will not be compressed.

# Optional Keywords
- `executable::Union{Nothing,Bool}=nothing`: Set to true to mark file as executable.
Defaults to false.
- `external_attr::Union{Nothing,UInt32}=nothing`: Manually set the 
external file attributes: See https://unix.stackexchange.com/questions/14705/the-zip-formats-external-file-attribute
"""
function zip_writefile(w::ZipWriter, name::AbstractString, data::AbstractVector{UInt8};
        executable::Union{Nothing,Bool}=nothing,
        external_attrs::Union{Nothing,UInt32}=nothing,
    )
    @argcheck isopen(w)
    zip_commitfile(w)
    namestr::String = String(name)
    @argcheck ncodeunits(namestr) ≤ typemax(UInt16)
    normed_name=nothing
    if w.check_names
        basic_name_check(namestr)
        @argcheck !isnothing(external_attrs) || !endswith(namestr, "/")
        normed_name = norm_name(namestr)
        @argcheck normed_name ∉ w.used_names_lower
    end
    @assert !iswritable(w)
    io = w._io
    crc32 = zip_crc32(data)
    pe = PartialEntry(;
        name=namestr,
        normed_name,
        offset=0,# place holder offset
        w.force_zip64,
        compressed_size=length(data),
        uncompressed_size=length(data),
        crc32,
    )
    if !isnothing(executable) && executable
        pe.external_attrs = UInt32(0o0100755)<<16
    end
    # Manual override of external_attrs
    if !isnothing(external_attrs)
        pe.external_attrs = external_attrs
    end
    write_local_header(io, pe)
    # sometimes position before a write is the read position.
    # That is why I am getting the offset after the write.
    pe.offset = position(io) - pe.local_header_size
    write(io, data) == length(data) || error("short write")
    @assert !iswritable(w)
    entry = append_entry!(w.central_dir_buffer, pe)
    if w.check_names
        push!(w.used_names_lower, something(pe.normed_name))
    end
    push!(w.entries, entry)
    nothing
end

"""
    zip_name_collision(w::ZipWriter, new_name::AbstractString)::Bool

Return true if `new_name` matches an existing committed entry.

The check is case insensitive, and 
insensitive to leading, trailing, and repeated `/`.
"""
zip_name_collision(w::ZipWriter, new_name::AbstractString)::Bool = zip_name_collision(w, String(new_name))
function zip_name_collision(w::ZipWriter, new_name::String)::Bool
    if w.check_names
        norm_name(new_name) ∈ w.used_names_lower
    else
        nname = norm_name(new_name)
        any(eachindex(w.entries)) do i
            nname == norm_name(String(_name_view(w, i)))
        end
    end
end

"""
    zip_mkdir(w::ZipWriter, name::AbstractString)

Write a directory entry named `name`.

`name` should end in "/". If not, a "/" will be appended.

This is only needed to add an empty directory.
"""
function zip_mkdir(w::ZipWriter, name::AbstractString)
    namestr::String = String(name)
    if !endswith(namestr, "/")
        namestr = namestr*"/"
    end
    zip_writefile(w, namestr, UInt8[];
        external_attrs=UInt32(0o0040755)<<16,
    )
end

"""
    zip_symlink(w::ZipWriter, target::AbstractString, link::AbstractString)

Creates a symbolic link to `target` with the name `link`.

This is not supported by most zip extractors. 
And will error unless `check_names` is set to `false` 
for the `ZipWriter`.
"""
function zip_symlink(w::ZipWriter, target::AbstractString, link::AbstractString)
    if w.check_names
        throw(ArgumentError("symlinks in zipfiles are not very portable"))
    end
    targetstr = String(target)
    namestr = String(link)
    zip_writefile(w, namestr, codeunits(targetstr);
        external_attrs=UInt32(0o0120755)<<16,
    )
end

function Base.close(w::ZipWriter)
    if !w.closed
        try
            zip_commitfile(w)
        finally
            w.partial_entry = nothing
            try
                write_footer(w._io, w.entries, w.central_dir_buffer; w.force_zip64)
            finally
                @assert isnothing(w.partial_entry)
                w.closed = true
                w._own_io && close(w._io)
            end
        end
    end
    nothing
end


need_zip64(entry::PartialEntry)::Bool = (
    entry.force_zip64                        ||
    entry.compressed_size   > typemax(Int32) ||
    entry.uncompressed_size > typemax(Int32) ||
    entry.offset            > typemax(Int32)
)

"""
Always writes 50 + ncodeunits(entry.name) bytes
"""
function write_local_header(io::IO, entry::PartialEntry)
    name_len::UInt16 = ncodeunits(entry.name)
    @assert entry.local_header_size == 50 + name_len
    b = zeros(UInt8, entry.local_header_size)
    p = 1

    use_zip64 = need_zip64(entry)
    version_needed = if use_zip64
        UInt16(45)
    else
        UInt16(20)
    end

    p += write_buffer(b, p, 0x04034b50) # local file header signature
    p += write_buffer(b, p, version_needed)
    p += write_buffer(b, p, entry.bit_flags)
    p += write_buffer(b, p, entry.method)
    p += write_buffer(b, p, entry.dos_time)
    p += write_buffer(b, p, entry.dos_date)
    p += write_buffer(b, p, entry.crc32)
    if use_zip64
        p += write_buffer(b, p, -1%UInt32) # compressed size placeholder
        p += write_buffer(b, p, -1%UInt32) # uncompressed size placeholder
    else
        p += write_buffer(b, p, UInt32(entry.compressed_size))
        p += write_buffer(b, p, UInt32(entry.uncompressed_size))
    end
    p += write_buffer(b, p, name_len) # file name length
    p += write_buffer(b, p, 0x0014) # extra field length
    p += write_buffer(b, p, entry.name)
    if use_zip64
        p += write_buffer(b, p, 0x0001) # Zip 64 Header ID
        p += write_buffer(b, p, 0x0010) # Local Zip 64 Length
        p += write_buffer(b, p, entry.uncompressed_size) # Original uncompressed file size
        p += write_buffer(b, p, entry.compressed_size) # Size of compressed data
    else
        # https://www.rubydoc.info/gems/rubyzip/1.2.1/Zip/ExtraField/Zip64Placeholder
        # https://sourceforge.net/p/sevenzip/discussion/45797/thread/4309fbc12f/
        p += write_buffer(b, p, 0x9999) # Zip 64 Placeholder Header ID
        p += write_buffer(b, p, 0x0010) # Local Zip 64 Length
        p += write_buffer(b, p, 0%UInt64) # Original uncompressed file size placeholder
        p += write_buffer(b, p, 0%UInt64) # Size of compressed data placeholder
    end
    @assert p == length(b)+1
    n = write(io, b)
    n == p-1 || error("short write")
    n
end

"""
Add the entry to the end of the central directory buffer `b`.
Also return an EntryInfo.
"""
function append_entry!(b::Vector{UInt8}, pe::PartialEntry)::EntryInfo
    use_zip64 = need_zip64(pe)
    version_needed = if use_zip64
        UInt16(45)
    else
        UInt16(20)
    end
    # Note these conversions can fail if the names
    # or comments are too long.
    name_len::UInt16 = ncodeunits(pe.name)
    comment_len::UInt16 = ncodeunits(pe.comment)
    extra_len::UInt16 = if use_zip64
        8*3+4
    else
        0
    end
    version_made = UInt8(45) # made by v4.5 equivalent
    os = UNIX

    old_len_b::Int = length(b)
    added_len::Int = 46 + Int(name_len) + Int(extra_len) + Int(comment_len)
    new_len_b::Int = old_len_b + added_len
    # make sure this doesn't overflow.
    @argcheck new_len_b > old_len_b
    resize!(b, new_len_b)
    p = old_len_b + 1
    p += write_buffer(b, p, 0x02014b50) # central file header signature
    p += write_buffer(b, p, version_made)
    p += write_buffer(b, p, os)
    p += write_buffer(b, p, version_needed)
    p += write_buffer(b, p, pe.bit_flags)
    p += write_buffer(b, p, pe.method)
    p += write_buffer(b, p, pe.dos_time)
    p += write_buffer(b, p, pe.dos_date)
    p += write_buffer(b, p, pe.crc32)
    if use_zip64
        p += write_buffer(b, p, -1%UInt32)
        p += write_buffer(b, p, -1%UInt32)
    else
        p += write_buffer(b, p, UInt32(pe.compressed_size))
        p += write_buffer(b, p, UInt32(pe.uncompressed_size))
    end
    p += write_buffer(b, p, name_len)
    p += write_buffer(b, p, extra_len)
    p += write_buffer(b, p, comment_len)
    # disk number start
    p += write_buffer(b, p, UInt16(0))
    # internal_attrs
    p += write_buffer(b, p, UInt16(0))
    p += write_buffer(b, p, pe.external_attrs)
    if use_zip64
        p += write_buffer(b, p, -1%UInt32)
    else
        p += write_buffer(b, p, UInt32(pe.offset))
    end
    p += write_buffer(b, p, pe.name)
    name_range = p-name_len:p-1
    if use_zip64
        p += write_buffer(b, p, 0x0001)
        p += write_buffer(b, p, UInt16(8*3))
        p += write_buffer(b, p, pe.uncompressed_size)
        p += write_buffer(b, p, pe.compressed_size)
        p += write_buffer(b, p, pe.offset)
    end
    p += write_buffer(b, p, pe.comment)
    comment_range = p-comment_len:p-1
    @assert p == length(b)+1
    
    EntryInfo(
        version_made,
        os,
        version_needed,
        pe.bit_flags,
        pe.method,
        pe.dos_time,
        pe.dos_date,
        pe.crc32,
        pe.compressed_size,
        pe.uncompressed_size,
        pe.offset,
        use_zip64,
        use_zip64,
        use_zip64,
        false,
        UInt16(0),
        pe.external_attrs,
        name_range,
        comment_range,
    )
end

function write_footer(
        io::IO,
        entries::Vector{EntryInfo},
        central_dir_buffer::Vector{UInt8};
        force_zip64::Bool=false
    )
    size_of_central_dir = write(io, central_dir_buffer)
    size_of_central_dir == length(central_dir_buffer) || error("short write")
    end_of_central_dir = position(io)
    @assert end_of_central_dir ≥ size_of_central_dir
    start_of_central_dir = end_of_central_dir - size_of_central_dir
    number_of_entries = length(entries)
    @argcheck number_of_entries ≤ size_of_central_dir>>5
    use_eocd64 = (
        force_zip64                           ||
        number_of_entries    > typemax(Int16) ||
        size_of_central_dir  > typemax(Int32) ||
        start_of_central_dir > typemax(Int32)
    )
    tailsize = 22
    if use_eocd64
        tailsize += 56 + 20
    end
    b = zeros(UInt8, tailsize)
    p = 1
    if use_eocd64
        p += write_buffer(b, p, 0x06064b50) # zip64 end of central dir signature
        p += write_buffer(b, p, UInt64(56-12)) # size of zip64 end of central directory record
        p += write_buffer(b, p, UInt8(45)) # version made by, zip v4.5 equivalent
        p += write_buffer(b, p, UNIX) # version made by OS
        p += write_buffer(b, p, UInt16(45)) # version needed to extract
        p += write_buffer(b, p, UInt32(0)) # number of this disk
        p += write_buffer(b, p, UInt32(0)) # number of the disk with the start of the central directory
        p += write_buffer(b, p, UInt64(number_of_entries)) # total number of entries in the central directory on this disk
        p += write_buffer(b, p, UInt64(number_of_entries)) # total number of entries in the central directory
        p += write_buffer(b, p, UInt64(size_of_central_dir)) # size of the central directory
        p += write_buffer(b, p, UInt64(start_of_central_dir)) # offset of start of central directory with respect to the starting disk number
        # empty zip64 extensible data sector

        p += write_buffer(b, p, 0x07064b50) # zip64 end of central dir locator signature
        p += write_buffer(b, p, UInt32(0)) # number of the disk with the start of the zip64 end of central directory
        p += write_buffer(b, p, UInt64(end_of_central_dir)) # relative offset of the zip64 end of central directory record
        p += write_buffer(b, p, UInt32(1)) # total number of disks
    end
    p += write_buffer(b, p, 0x06054b50) # end of central dir signature
    p += write_buffer(b, p, UInt16(0)) # number of this disk
    p += write_buffer(b, p, UInt16(0)) # number of the disk with the start of the central directory
    p += write_buffer(b, p, UInt16(min(number_of_entries, -1%UInt16))) # total number of entries in the central directory on this disk
    p += write_buffer(b, p, UInt16(min(number_of_entries, -1%UInt16))) # total number of entries in the central directory
    p += write_buffer(b, p, UInt32(min(size_of_central_dir, -1%UInt32))) # size of the central directory
    p += write_buffer(b, p, UInt32(min(start_of_central_dir, -1%UInt32))) # offset of start of central directory with respect to the starting disk number
    p += write_buffer(b, p, UInt16(0)) # .ZIP file comment length
    # empty .ZIP file comment
    @assert p == length(b)+1
    n = write(io, b)
    n == p-1 || error("short write")
    after_write_offset = position(io)
    @argcheck after_write_offset == tailsize + end_of_central_dir
    tailsize + size_of_central_dir
end