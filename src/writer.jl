using ArgCheck
using CodecZlib
using TranscodingStreams


"""
    mutable struct ZipWriter <: IO
    ZipWriter(io::IO; zip_kwargs...)
    ZipWriter(f::Function, io::IO; zip_kwargs...)

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
        entries, central_dir_offset = parse_central_directory(io)
        if trunc_footer
            truncate(io, central_dir_offset)
            seekend(io)
        else
            seekend(io)
        end
        w = ZipWriter(io, zip_kwargs...)
        w.entries = entries
        if w.check_names
            w.used_names_lower = Set{String}(lowercase(e.name) for e in entries)
        end
    catch # close io if there is an error parsing entries
        if zip_kwargs.own_io
            close(io)
        end
        rethrow()
    end
end
function zip_append_archive(f::Function, io::IO; kwargs...)::ZipWriter
    w = zip_appendzip(io; kwargs...)
    try
        f(w)
    finally
        close(w)
    end
    w
end
function zip_append_archive(filename::AbstractString; open_kwargs...)
    zip_appendzip(
        Base.open(filename; read=true, write=true, open_kwargs...);
        zip_kwargs=(;own_io=true)
    )
end
function zip_append_archive(f::Function, filename::AbstractString; open_kwargs...)
    zip_appendzip(
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
- `compression_method=Store`: `Store` is uncompressed 
`Deflate` is compressed.
- `compression_level::Union{Nothing,Int}=nothing`: 
For `Deflate` defaults to -1 and can be -1 or 0 to 9.
1 is fastest, 9 is smallest file size. 
0 is no compression, and -1 is a good compromise between speed and file size.
- `executable::Union{Nothing,Bool}=nothing`: Set to true to mark file as executable.
Defaults to false.
"""
function zip_newfile(w::ZipWriter, name::AbstractString; 
        compression_method::UInt16=Store,
        compression_level::Union{Nothing,Int}=nothing,
        executable::Union{Nothing,Bool}=nothing,
    )
    @argcheck isopen(w)
    zip_commitfile(w)
    namestr = String(name)
    @argcheck ncodeunits(namestr) ≤ typemax(UInt16)
    if w.check_names
        basic_name_check(namestr)
        @argcheck !endswith(namestr, "/")
        @argcheck lowercase(namestr) ∉ w.used_names_lower
    end
    @assert !iswritable(w)
    io = w._io
    offset = position(io)
    entry = EntryInfo(;name=namestr, offset)
    if !isnothing(executable) && executable
        entry.external_attrs = UInt32(0o0100755)<<16
    end
    if w.force_zip64
        entry.c_size_zip64 = true
        entry.u_size_zip64 = true
        entry.offset_zip64 = true
        entry.version_needed = 45
    end
    codec, level_bits = if compression_method==Store
        (Noop(), 0)
    elseif compression_method==Deflate
        if isnothing(compression_level)
            compression_level = -1
        end
        @argcheck compression_level ∈ (-1:9)
        (
            DeflateCompressor(;level = compression_level),
            deflate_level_bits(compression_level),
        )
    else
        throw(ArgumentError("compression_method must be Deflate or Store"))
    end
    entry.method = compression_method
    entry.bit_flags |= level_bits
    local_header_size = write_local_header(io, entry)
    w.partial_entry = PartialEntry(
        entry,
        local_header_size,
        TranscodingStream(codec, io),
    )
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
    b[p:p+length(x)-1] .= x
    length(x)
end
function write_buffer(b::Vector{UInt8}, p::Int, x::String)::Int
    write_buffer(b, p, codeunits(x))
end

"""
Always writes normal_local_header_size(entry) bytes
"""
function write_local_header(io::IO, entry::EntryInfo)
    name_len::UInt16 = ncodeunits(entry.name)
    b = zeros(UInt8, normal_local_header_size(entry))
    p = 1
    # Check for unsupported bit flags
    @argcheck iszero(entry.bit_flags & 1<<3) "writing data descriptor not supported."
    @argcheck !iszero(entry.bit_flags & 1<<11) "UTF-8 encoding is required."
    @argcheck iszero(entry.bit_flags & 1<<13) "encrypted files not supported."

    use_zip64 = need_zip64(entry)
    p += write_buffer(b, p, 0x04034b50) # local file header signature
    if use_zip64
        @argcheck entry.version_needed ≥ 45
    else
        @argcheck entry.version_needed ≥ 20
    end
    p += write_buffer(b, p, entry.version_needed)
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
    pe::PartialEntry = w.partial_entry
    nb::UInt = unsafe_write(pe.transcoder, p, n)
    pe.entry.crc32 = unsafe_crc32(p, nb, pe.entry.crc32)
    pe.entry.uncompressed_size += nb
    # pe.entry.compressed_size is updated in zip_commitfile
    nb
end

function Base.position(w::ZipWriter)::Int64
    assert_writeable(w)
    w.partial_entry.entry.uncompressed_size
end

function normalize_zip64!(entry::EntryInfo, force_zip64=false)
    use_zip64 = (
        force_zip64 ||
        entry.compressed_size   > typemax(Int32) ||
        entry.uncompressed_size > typemax(Int32) ||
        entry.offset > typemax(Int32)
    )
    if use_zip64
        entry.c_size_zip64 = true
        entry.u_size_zip64 = true
        entry.offset_zip64 = true
        entry.n_disk_zip64 = false
        entry.version_needed = max(entry.version_needed, UInt16(45))
        b = zeros(UInt8, 8*3)
        p = 1
        p += write_buffer(b, p, entry.uncompressed_size)
        p += write_buffer(b, p, entry.compressed_size)
        p += write_buffer(b, p, entry.offset)
        entry.central_extras = [ExtraField(0x0001, b)]
    end
    nothing
end

"""
    zip_commitfile(w::ZipWriter)
Close any open entry making `w` not writable.
If there is some error, this will behave like [`zip_abortfile`](@ref)
then rethrow the error.
"""
function zip_commitfile(w::ZipWriter)
    if iswritable(w)
        pe::PartialEntry = w.partial_entry
        entry::EntryInfo = pe.entry
        w.partial_entry = nothing
        # If some error happens, the file will be partially written,
        # but not included in the central directory.
        # Finish the compressing here, but don't close underlying IO.
        try
            write(pe.transcoder, TranscodingStreams.TOKEN_END)
        finally
            # Prevent memory leak maybe.
            TranscodingStreams.finalize(pe.transcoder.codec)
        end

        pe.entry.compressed_size = position(w._io) - entry.offset - pe.local_header_size
        normalize_zip64!(entry, w.force_zip64)
        
        # note, make sure never to change the partial_entry except for these three things.
        @assert normal_local_header_size(entry) == pe.local_header_size
        if !all(iszero, (entry.uncompressed_size, entry.compressed_size, entry.crc32))
            # Must go back and update the local header if any data was written.
            cur_offset = position(w._io)
            try
                # TODO add better error message about requiring seekable IO if this fails
                seek(w._io, entry.offset)
                write_local_header(w._io, entry)
            finally
                seek(w._io, cur_offset)
            end
        end
        if w.check_names
            push!(w.used_names_lower, lowercase(entry.name))
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
        pe::PartialEntry = w.partial_entry
        w.partial_entry = nothing
        # Finish the compressing here, but don't close underlying IO.
        try
            write(pe.transcoder, TranscodingStreams.TOKEN_END)
        finally
            # Prevent memory leak maybe.
            TranscodingStreams.finalize(pe.transcoder.codec)
        end
    end
    nothing
end

"""
    zip_writefile(w::ZipWriter, name::AbstractString, data::AbstractVector{UInt8})

Write data as a file entry named `name`.

Unlike zip_newfile, the wrapped IO doesn't need to be seekable.
`w` isn't writable after. The written data will not be compressed.
"""
function zip_writefile(w::ZipWriter, name::AbstractString, data::AbstractVector{UInt8})
    @argcheck isopen(w)
    zip_commitfile(w)
    namestr = String(name)
    @argcheck ncodeunits(namestr) ≤ typemax(UInt16)
    if w.check_names
        basic_name_check(namestr)
        @argcheck !endswith(namestr, "/")
        @argcheck lowercase(namestr) ∉ w.used_names_lower
    end
    @assert !iswritable(w)
    io = w._io
    offset = position(io)
    crc32 = zip_crc32(data)
    entry = EntryInfo(;
        name=namestr,
        offset,
        compressed_size=length(data),
        uncompressed_size=length(data),
        crc32,
    )
    normalize_zip64!(entry, w.force_zip64)
    write_local_header(io, entry)
    write(io, data) == length(data) || error("short write")
    @assert !iswritable(w)
    if w.check_names
        push!(w.used_names_lower, lowercase(entry.name))
    end
    push!(w.entries, entry)
    entry
end

"""
    zip_mkdir(w::ZipWriter, name::AbstractString)

Write a directory entry named `name`.

`name` should end in "/". If not it will be added.

This is only needed to add an empty directory.
"""
function zip_mkdir(w::ZipWriter, name::AbstractString)
    @argcheck isopen(w)
    zip_commitfile(w)
    namestr = String(name)
    if !endswith(namestr, "/")
        namestr = namestr*"/"
    end
    @argcheck ncodeunits(namestr) ≤ typemax(UInt16)
    if w.check_names
        basic_name_check(namestr)
        @assert endswith(namestr, "/")
        @argcheck lowercase(namestr) ∉ w.used_names_lower
    end
    @assert !iswritable(w)
    io = w._io
    offset = position(io)
    entry = EntryInfo(;
        name=namestr,
        offset,
        external_attrs = UInt32(0o0040755)<<16,
    )
    normalize_zip64!(entry, w.force_zip64)
    write_local_header(io, entry)
    @assert !iswritable(w)
    if w.check_names
        push!(w.used_names_lower, lowercase(entry.name))
    end
    push!(w.entries, entry)
    entry
end

"""
Just write whatever is in entry, don't normalize or check for issues here.
"""
function write_central_header(io::IO, entry::EntryInfo)
    name_len::UInt16 = ncodeunits(entry.name)
    extra_len::UInt16 = sum(entry.central_extras; init=0) do extra::ExtraField
        4 + length(extra.data)
    end
    comment_len::UInt16 = ncodeunits(entry.comment)
    b = zeros(UInt8, 46 + Int(name_len) + Int(extra_len) + Int(comment_len))
    p = 1
    p += write_buffer(b, p, 0x02014b50) # central file header signature
    p += write_buffer(b, p, entry.version_made)
    p += write_buffer(b, p, entry.os)
    p += write_buffer(b, p, entry.version_needed)
    p += write_buffer(b, p, entry.bit_flags)
    p += write_buffer(b, p, entry.method)
    p += write_buffer(b, p, entry.dos_time)
    p += write_buffer(b, p, entry.dos_date)
    p += write_buffer(b, p, entry.crc32)
    if entry.c_size_zip64
        p += write_buffer(b, p, -1%UInt32)
    else
        p += write_buffer(b, p, UInt32(entry.compressed_size))
    end
    if entry.u_size_zip64
        p += write_buffer(b, p, -1%UInt32)
    else
        p += write_buffer(b, p, UInt32(entry.uncompressed_size))
    end
    p += write_buffer(b, p, name_len)
    p += write_buffer(b, p, extra_len)
    p += write_buffer(b, p, comment_len)
    if entry.n_disk_zip64 # disk number start
        p += write_buffer(b, p, -1%UInt16)
    else
        p += write_buffer(b, p, UInt16(0))
    end
    p += write_buffer(b, p, entry.internal_attrs)
    p += write_buffer(b, p, entry.external_attrs)
    if entry.offset_zip64
        p += write_buffer(b, p, -1%UInt32)
    else
        p += write_buffer(b, p, UInt32(entry.offset))
    end
    p += write_buffer(b, p, entry.name)
    for extra in entry.central_extras
        p += write_buffer(b, p, extra.id)
        p += write_buffer(b, p, UInt16(length(extra.data)))
        p += write_buffer(b, p, extra.data)
    end
    p += write_buffer(b, p, entry.comment)
    @assert p == length(b)+1
    n = write(io, b)
    n == p-1 || error("short write")
    n
end

function write_footer(io::IO, entries::Vector{EntryInfo}; force_zip64::Bool=false)
    start_of_central_dir = position(io)
    for entry in entries
        write_central_header(io, entry)
    end
    end_of_central_dir = position(io)
    size_of_central_dir = end_of_central_dir - start_of_central_dir
    number_of_entries = length(entries)
    use_eocd64 = (
        force_zip64 ||
        number_of_entries > typemax(Int16) ||
        size_of_central_dir > typemax(Int32) ||
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
        p += write_buffer(b, p, UInt8(63)) # version made by zip 6.3
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
    tailsize + size_of_central_dir
end

function Base.close(w::ZipWriter)
    if !w.closed
        try
            zip_commitfile(w)
        finally
            w.partial_entry = nothing
            try
                write_footer(w._io, w.entries; w.force_zip64)
            finally
                @assert isnothing(w.partial_entry)
                w.closed = true
                w._own_io && close(w._io)
            end
        end
    end
    nothing
end
