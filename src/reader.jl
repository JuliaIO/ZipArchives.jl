function unsafe_crc32(p::Ptr{UInt8}, nb::UInt, crc::UInt32)::UInt32
    ccall((:crc32_z, Zlib_jll.libz),
        Culong, (Culong, Ptr{UInt8}, Csize_t),
        crc, p, nb,
    )
end

# currently unsafe_convert fails on some AbstractUnitRange{<:Integer}, so plain `AbstractUnitRange` can't be used
const FastByteView{P <: AbstractVector{UInt8}} = SubArray{UInt8, 1, P, <:Tuple{AbstractUnitRange{Int}}, true}

if VERSION ≥ v"1.11"
    const ByteArray = Union{
        Base.CodeUnits{UInt8, String},
        Vector{UInt8},
        FastByteView{Base.CodeUnits{UInt8,String}}, 
        FastByteView{Vector{UInt8}},
        Memory{UInt8},
        FastByteView{Memory{UInt8}}
    }
else
    const ByteArray = Union{
        Base.CodeUnits{UInt8, String},
        Vector{UInt8},
        FastByteView{Base.CodeUnits{UInt8,String}},
        FastByteView{Vector{UInt8}}
    }
end

# version of String(v::AbstractVector{UInt8}) that works consistently.
function bytes2string(v::AbstractVector{UInt8})::String
    String(view(v,:))
end

"""
    zip_crc32(data::AbstractVector{UInt8}, crc::UInt32=UInt32(0))::UInt32

Return the standard zip CRC32 checksum of data

See also [`zip_stored_crc32`](@ref), [`zip_test_entry`](@ref).
"""
function zip_crc32(data::ByteArray, crc::UInt32=UInt32(0))::UInt32
    cconv_data = Base.cconvert(Ptr{UInt8}, data)
    GC.@preserve cconv_data unsafe_crc32(Base.unsafe_convert(Ptr{UInt8}, cconv_data), UInt(length(data)), crc)
end

function zip_crc32(data::AbstractVector{UInt8}, crc::UInt32=UInt32(0))::UInt32
    start::Int64 = firstindex(data)
    n::Int64 = length(data)
    offset::Int64 = 0
    buf = Vector{UInt8}(undef, min(n, Int64(24576)))
    while offset < n
        nb = min(n-offset, Int64(24576))
        copyto!(buf, Int64(1), data, offset + start, nb)
        crc = zip_crc32(view(buf, 1:Int(nb)), crc)
        offset += nb
    end
    crc
end

@inline readle(io::IO, ::Type{UInt64}) = UInt64(readle(io, UInt32)) | UInt64(readle(io, UInt32))<<32
@inline readle(io::IO, ::Type{UInt32}) = UInt32(readle(io, UInt16)) | UInt32(readle(io, UInt16))<<16
@inline readle(io::IO, ::Type{UInt16}) = UInt16(read(io, UInt8)) | UInt16(read(io, UInt8))<<8
@inline readle(io::IO, ::Type{UInt8}) = read(io, UInt8)

# @inline readle(v, offset, ::Type{UInt64}) = UInt64(readle(v, offset, UInt32)) | UInt64(readle(v, offset+4, UInt32))<<32
@inline readle(v, offset, ::Type{UInt32}) = UInt32(readle(v, offset, UInt16)) | UInt32(readle(v, offset+2, UInt16))<<16
@inline readle(v, offset, ::Type{UInt16}) = UInt16(readle(v, offset, UInt8 )) | UInt16(readle(v, offset+1, UInt8 ))<<8
@inline readle(v, offset, ::Type{UInt8}) = v[begin+offset]

function getchunk(io::IO, offset, size)
    seek(io, offset)
    out = read(io, size)
    if length(out) != size
        error("short read")
    end
    out
end
function getchunk(io::InputBuffer{<:ByteArray}, offset, size)
    data = parent(io)
    start = firstindex(data)+offset
    view(data, start:start+size-1)
end

#=
Return the minimum size of a local header for an entry.
=#
min_local_header_size(entry::EntryInfo)::Int64 = 30 + length(entry.name_range)

"""
    const HasEntries = Union{ZipReader, ZipWriter}
"""
const HasEntries = Union{ZipReader, ZipWriter}

"""
    const ZipBufferReader = ZipReader
"""
const ZipBufferReader = ZipReader

# Getters
"""
    zip_nentries(x::HasEntries)::Int

Return the number of entries in `x`.
"""
zip_nentries(x::HasEntries)::Int = length(x.entries)

"""
    zip_name(x::HasEntries, i::Integer)::String

Return the name of entry `i`.

`i` can range from `1:zip_nentries(x)`
"""
zip_name(x::HasEntries, i::Integer)::String = bytes2string(_name_view(x, i))

"""
    zip_names(x::HasEntries)::Vector{String}

Return the names of the entries.
"""
zip_names(x::HasEntries)::Vector{String} = String[zip_name(x,i) for i in 1:zip_nentries(x)]

"""
    zip_uncompressed_size(x::HasEntries, i::Integer)::UInt64

Return the marked uncompressed size of entry `i` in number of bytes.

Note: if the zip file was corrupted, this might be wrong.
"""
zip_uncompressed_size(x::HasEntries, i::Integer)::UInt64 = x.entries[i].uncompressed_size

"""
    zip_compressed_size(x::HasEntries, i::Integer)::UInt64

Return the marked compressed size of entry `i` in number of bytes.

Note: if the zip file was corrupted, this might be wrong.
"""
zip_compressed_size(x::HasEntries, i::Integer)::UInt64 = x.entries[i].compressed_size

"""
    zip_compression_method(x::HasEntries, i::Integer)::UInt16

Return the compression method used for entry `i`.

See https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT for a current list of methods.

Only Store(0), Deflate(8), and Deflate64(9) are supported for now.

Note: if the zip file was corrupted, this might be wrong.
"""
zip_compression_method(x::HasEntries, i::Integer)::UInt16 = x.entries[i].method

"""
    zip_general_purpose_bit_flag(x::HasEntries, i::Integer)::UInt16

Return the general purpose bit flag for entry `i`.

See https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT 
for a description of the bits.
"""
zip_general_purpose_bit_flag(x::HasEntries, i::Integer)::UInt16 = x.entries[i].bit_flags

"""
    zip_iscompressed(x::HasEntries, i::Integer)::Bool

Return if entry `i` is marked as compressed.
"""
zip_iscompressed(x::HasEntries, i::Integer)::Bool = x.entries[i].method != Store

"""
    zip_comment(x::HasEntries, i::Integer)::String

Return the comment attached to entry `i`
"""
zip_comment(x::HasEntries, i::Integer)::String = bytes2string(view(x.central_dir_buffer, x.entries[i].comment_range))

"""
    zip_stored_crc32(x::HasEntries, i::Integer)::UInt32

Return the marked crc32 of entry `i` in the central directory.

Note: if the zip file was corrupted, this might be wrong.

See also [`zip_crc32`](@ref), [`zip_test_entry`](@ref).
"""
zip_stored_crc32(x::HasEntries, i::Integer)::UInt32 = x.entries[i].crc32

_name_view(x::HasEntries, i::Integer) = view(x.central_dir_buffer, x.entries[i].name_range)

"""
    zip_definitely_utf8(x::HasEntries, i::Integer)::Bool

Return true if entry `i` name is marked as utf8 or is ascii.

Otherwise, the name should probably be treated as a sequence of bytes.

This package will never attempt to transcode filenames.
"""
function zip_definitely_utf8(x::HasEntries, i::Integer)::Bool
    entry = x.entries[i]
    name_view = _name_view(x, i)
    (
        all(<(0x80), name_view) || # isascii
        !iszero(entry.bit_flags & UInt16(1<<11)) && isvalid(String, name_view)
    )
end

"""
    zip_isdir(x::HasEntries, i::Integer)::Bool

Return if entry `i` is a directory.
"""
zip_isdir(x::HasEntries, i::Integer)::Bool = _name_view(x, i)[end] == UInt8('/')

"""
    zip_isdir(x::HasEntries, s::AbstractString)::Bool

Return if `s` is an implicit or explicit directory in `x`
"""
zip_isdir(x::HasEntries, s::AbstractString)::Bool = zip_isdir(x, String(s))
function zip_isdir(x::HasEntries, s::String)::Bool
    data = collect(codeunits(s))
    if isempty(data) || data[end] != UInt8('/')
        push!(data, UInt8('/'))
    end
    prefix_len = length(data)
    b = x.central_dir_buffer
    any(x.entries) do e
        name_range = e.name_range
        (
            length(name_range) ≥ prefix_len &&
            data == view(b, name_range[1]:name_range[prefix_len])
        )::Bool
    end
end

"""
    zip_findlast_entry(x::HasEntries, s::AbstractString)::Union{Nothing, Int}

Return the index of the last entry with name `s` or `nothing` if not found.
"""
zip_findlast_entry(x::HasEntries, s::AbstractString)::Union{Nothing, Int} = zip_findlast_entry(x, String(s))
function zip_findlast_entry(x::HasEntries, s::String)::Union{Nothing, Int}
    data = codeunits(s)
    n = length(data)
    findlast(x.entries) do e
        n == length(e.name_range) && view(x.central_dir_buffer, e.name_range) == data
    end
end

"""
    zip_isexecutablefile(x::HasEntries, i::Integer)::Bool

Return if entry `i` is marked as a UNIX executable file.
"""
function zip_isexecutablefile(x::HasEntries, i::Integer)::Bool
    entry = x.entries[i]
    (
        entry.os == UNIX &&
        !iszero(entry.external_attrs & (UInt32(0o100)<<16)) &&
        (entry.external_attrs>>(32-4)) == 0o10
    )
end

"""
    zip_test_entry(x::ZipReader, i::Integer)::Nothing

If entry `i` has an issue, error.
Otherwise, return nothing.

This will also read the entry and check the crc32 matches.
"""
function zip_test_entry(r::ZipReader, i::Integer)::Nothing
    saved_uncompressed_size = zip_uncompressed_size(r, i)
    @argcheck saved_uncompressed_size < typemax(Int64)
    saved_crc32 = zip_stored_crc32(r, i)
    zip_openentry(r, i) do io
        real_crc32::UInt32 = 0
        uncompressed_size::UInt64 = 0
        buffer = zeros(UInt8, 1<<14)
        while !eof(io)
            nb = readbytes!(io, buffer)
            @argcheck uncompressed_size < typemax(Int64)
            uncompressed_size += nb
            @argcheck uncompressed_size ≤ saved_uncompressed_size
            real_crc32 = zip_crc32(view(buffer, 1:Int(nb)), real_crc32)
        end
        @argcheck uncompressed_size === saved_uncompressed_size
        @argcheck saved_crc32 == real_crc32
    end
    nothing
end

"""
    zip_test(r::ZipReader)::Nothing

Test all entries in the archive in order from `1` to `zip_nentries(r)`
Throw an error for the first invalid entry.
"""
function zip_test(r::ZipReader)::Nothing
    for i in 1:zip_nentries(r)
        try
            zip_test_entry(r, i)
        catch
            error("entry $(i): $(repr(zip_name(r, i))) is invalid")
        end
    end
    nothing
end

"""
    zip_openentry(r::ZipReader, i::Union{AbstractString, Integer})
    zip_openentry(f::Function, r::ZipReader, i::Union{AbstractString, Integer})

Open entry `i` from `r` as a readable IO.

If `i` is a string open the last entry with the exact matching name.

Make sure to close the returned stream when done reading, 
if not using the do block method.

The stream returned by this function
should only be accessed by one thread at a time.

See also [`zip_readentry`](@ref).
"""
function zip_openentry(f::Function, r::ZipReader, i::Union{AbstractString, Integer})
    io = zip_openentry(r, i)
    try
        f(io)
    finally
        close(io)
    end
end
zip_openentry(r::ZipReader, i::Integer) = zip_openentry(r, Int(i))
function zip_openentry(r::ZipReader, s::AbstractString)
    i = zip_findlast_entry(r, s)
    isnothing(i) && throw(ArgumentError("entry with name $(repr(s)) not found"))
    zip_openentry(r, i)
end



"""
    zip_readentry(r::ZipReader, i::Union{AbstractString, Integer}, args...; kwargs...)

Read the contents of entry `i` in `r`.

If `i` is a string read the last entry with the exact matching name.

`args...; kwargs...` are passed on to `read`
after the entry `i` in zip reader `r` is opened with [`zip_openentry`](@ref)

if `args...` are empty or `String`, this will also error if the checksum doesn't match.

See also [`zip_openentry`](@ref).
"""
zip_readentry(r::ZipReader, i::Union{AbstractString, Integer}, args...; kwargs...) = zip_openentry(io -> read(io, args...; kwargs...), r, i)

function zip_readentry(r::ZipReader, i::Integer)
    saved_uncompressed_size = Int(zip_uncompressed_size(r, i))
    @argcheck saved_uncompressed_size < typemax(Int64)
    data = zip_openentry(r, i) do io
        _d = read(io, saved_uncompressed_size)
        @argcheck length(_d) == saved_uncompressed_size
        @argcheck eof(io)
        _d
    end
    saved_crc32 = zip_stored_crc32(r, i)
    real_crc32 = zip_crc32(data)
    @argcheck saved_crc32 == real_crc32
    data
end
function zip_readentry(r::ZipReader, s::AbstractString)
    i = zip_findlast_entry(r, s)
    isnothing(i) && throw(ArgumentError("entry with name $(repr(s)) not found"))
    zip_readentry(r, i)
end

function zip_readentry(r::ZipReader, i::Union{AbstractString, Integer}, ::Type{String})
    bytes2string(zip_readentry(r, i))
end

struct EOCDRecord
    "number of this disk, or -1"
    disk16::UInt16

    "number of the disk with the start of the central directory or -1"
    cd_disk16::UInt16

    "total number of entries in the central directory on this disk"
    num_entries_thisdisk16::UInt16

    "total number of entries in the central directory or -1"
    num_entries16::UInt16

    "size of the central directory or -1"
    central_dir_size32::UInt32

    "offset of start of central directory with respect to the starting disk number or -1"
    central_dir_offset32::UInt32

    "The length of the comment for this .ZIP file."
    comment_len::UInt16
end

# If this fails, io isn't a zip file, io isn't seekable, 
# or the end of the zip file was corrupted
# Using yauzl method https://github.com/thejoshwolfe/yauzl/blob/51010ce4e8c7e6345efe195e1b4150518f37b393/index.js#L111-L113
function parse_end_of_central_directory_record(io::IO, fsize)::EOCDRecord
    min_eocd_len = 22
    fsize ≥ min_eocd_len || throw(ArgumentError("io isn't a zip file. Too small"))
    chunk = getchunk(io, fsize-min_eocd_len, min_eocd_len)
    eocd_chunk = if readle(chunk, 0, UInt32) == 0x06054b50
        @view(chunk[begin+4:end])
    else
        max_comment_len = min(0xFFFF, fsize-22)
        max_eocd_len = max_comment_len + min_eocd_len
        chunk = getchunk(io, fsize-max_eocd_len, max_eocd_len)
        comment_len = -1
        for i in 1:max_comment_len
            if readle(chunk, max_comment_len-i, UInt32) == 0x06054b50
                comment_len = i
                break
            end
        end
        if comment_len == -1
            throw(ArgumentError("""
                io isn't a zip file. 
                It may be a zip file with a corrupted ending.
                """
            ))
        end
        @view(chunk[begin+max_comment_len-comment_len+4:end])
    end
    eocd = EOCDRecord(
        readle(eocd_chunk, 0, UInt16),
        readle(eocd_chunk, 2, UInt16),
        readle(eocd_chunk, 4, UInt16),
        readle(eocd_chunk, 6, UInt16),
        readle(eocd_chunk, 8, UInt32),
        readle(eocd_chunk, 12, UInt32),
        readle(eocd_chunk, 16, UInt16),
    )
    if eocd.comment_len + 18 != length(eocd_chunk)
        throw(ArgumentError("""
            io isn't a zip file. 
            It may be a zip file with a corrupted ending.
            """
        ))
    end
    # Only one disk with num 0 is supported.
    if eocd.disk16 != -1%UInt16
        @argcheck eocd.disk16 == 0
    end
    if eocd.cd_disk16 != -1%UInt16
        @argcheck eocd.cd_disk16 == 0
    end
    eocd
end

function parse_EOCD64(io::IO, fsize, eocd::EOCDRecord)::NTuple{3,Int64}
    eocd_offset = fsize - 22 - eocd.comment_len
    (
        eocd.disk16                 == -1%UInt16 ||
        eocd.cd_disk16              == -1%UInt16 ||
        eocd.num_entries_thisdisk16 == -1%UInt16 ||
        eocd.num_entries16          == -1%UInt16 ||
        eocd.central_dir_size32     == -1%UInt32 ||
        eocd.central_dir_offset32   == -1%UInt32
    ) || @goto nonzip64
    # Parse the ZIP64 end of central directory record
    # It may be that one of the values just happens to be -1
    # so on some errors @goto nonzip64
    eocd_offset ≥ 56+20 || @goto nonzip64
    # Optimistically try to read both the zip64 end of central directory record
    # and the zip64 end of central directory locator
    # the zip64 extensible data sector may be huge requiring a latter read.
    chunk_offset = eocd_offset - (56+20)
    chunk = getchunk(io, chunk_offset, 56+20)
    locator_io = InputBuffer(@view(chunk[begin+56:end]))
    readle(locator_io, UInt32) == 0x07064b50 || @goto nonzip64
    # number of the disk with the start of the zip64 end of central directory
    # Only one disk with num 0 is supported.
    readle(locator_io, UInt32) == 0 || @goto nonzip64
    eocd64_offset = readle(locator_io, UInt64)
    total_num_disks = readle(locator_io, UInt32)
    total_num_disks ≤ 1 || @goto nonzip64
    eocd64_offset ≤ eocd_offset - (56+20) || @goto nonzip64
    record_io = if eocd64_offset == chunk_offset
        # The record is already in chunk
        InputBuffer(chunk)
    elseif eocd64_offset < chunk_offset
        # read in a new chunk, there may be data in the zip64 extensible data sector
        InputBuffer(getchunk(io, eocd64_offset, 56))
    else
        @goto nonzip64
    end
    # zip64 end of central dir signature
    readle(record_io, UInt32) == 0x06064b50 || @goto nonzip64

    # Parse Zip64 end of central directory record
    # At this point error if not valid

    # size of zip64 end of central directory record
    skip(record_io, 8)
    # version made by
    skip(record_io, 2)
    # version needed to extract
    # This is set to 62 if version 2 of ZIP64 is used
    # This is not supported yet.
    version_needed = readle(record_io, UInt16) & 0x00FF
    @argcheck version_needed < 62
    # number of this disk
    @argcheck readle(record_io, UInt32) == 0
    # number of the disk with the start of the central directory
    @argcheck readle(record_io, UInt32) == 0
    # total number of entries in the central directory on this disk
    num_entries_thisdisk64 = readle(record_io, UInt64)
    # total number of entries in the central directory
    num_entries64 = readle(record_io, UInt64)
    @argcheck num_entries64 == num_entries_thisdisk64
    if eocd.num_entries16 != -1%UInt16
        @argcheck num_entries64 == eocd.num_entries16
    end
    if eocd.num_entries_thisdisk16 != -1%UInt16
        @argcheck num_entries64 == eocd.num_entries_thisdisk16
    end
    # size of the central directory
    central_dir_size64 = readle(record_io, UInt64)
    if eocd.central_dir_size32 != -1%UInt32
        @argcheck central_dir_size64 == eocd.central_dir_size32
    end
    @argcheck central_dir_size64 ≤ eocd64_offset
    # offset of start of central directory with respect to the starting disk number
    central_dir_offset64 = readle(record_io, UInt64)
    if eocd.central_dir_offset32 != -1%UInt32
        @argcheck central_dir_offset64 == eocd.central_dir_offset32
    end
    @argcheck central_dir_offset64 ≤ eocd64_offset - central_dir_size64
    return (Int64(central_dir_offset64), Int64(central_dir_size64), Int64(num_entries64))
    @label nonzip64
    begin
        @argcheck eocd.disk16 == 0
        @argcheck eocd.cd_disk16 == 0
        @argcheck eocd.num_entries16 == eocd.num_entries_thisdisk16
        @argcheck eocd.central_dir_size32 ≤ eocd_offset
        @argcheck eocd.central_dir_offset32 ≤ eocd_offset - eocd.central_dir_size32
        return (Int64(eocd.central_dir_offset32), Int64(eocd.central_dir_size32), Int64(eocd.num_entries16))
    end
end

"""
    parse_central_directory(io::IO)::Tuple{Vector{EntryInfo}, Vector{UInt8}, Int64}

Where `io` must be readable and seekable.
`io` is assumed to not be changed while this function runs.

Return the entries, the raw data of the central directory, and the offset in `io` of the start of the central directory as a named tuple. `(;entries, central_dir_buffer, central_dir_offset)`

The central directory is after all entry data.

"""
function parse_central_directory(io::IO)
    seekend(io)
    fsize = position(io)
    # 1st find end of central dir section
    eocd = parse_end_of_central_directory_record(io, fsize)
    
    # 2nd find where the central dir is and 
    # how many entries there are.
    # This is confusing because of ZIP64 and disk number weirdness.
    central_dir_offset::Int64, central_dir_size::Int64, num_entries::Int64 = parse_EOCD64(io, fsize, eocd)
    # If num_entries is crazy high, avoid allocating crazy amount of memory
    # The minimum entry size is 46
    min_central_dir_size, num_entries_overflow = Base.mul_with_overflow(num_entries, Int64(46))
    @argcheck !num_entries_overflow
    @argcheck min_central_dir_size ≤ central_dir_size
    seek(io, central_dir_offset)
    central_dir_buffer::Vector{UInt8} = read(io, central_dir_size)
    @argcheck length(central_dir_buffer) == central_dir_size
    entries = parse_central_directory_headers!(central_dir_buffer, num_entries)

    (;entries, central_dir_buffer, central_dir_offset)
end

function parse_central_directory_headers!(central_dir_buffer::Vector{UInt8}, num_entries::Int64)::Vector{EntryInfo}
    io_b = InputBuffer(central_dir_buffer)
    seekstart(io_b)
    # parse central directory headers
    entries = Vector{EntryInfo}(undef, num_entries)
    for i in 1:num_entries
        @argcheck bytesavailable(io_b) ≥ 46
        # central file header signature
        @argcheck readle(io_b, UInt32) == 0x02014b50
        version_made = readle(io_b, UInt8)
        os = readle(io_b, UInt8)
        # An old version of 7zip added the OS byte to version needed. So ignore the top byte here. https://sourceforge.net/p/sevenzip/bugs/1019/
        version_needed = readle(io_b, UInt16) & 0x00FF
        bit_flags = readle(io_b, UInt16)
        method = readle(io_b, UInt16)
        dos_time = readle(io_b, UInt16)
        dos_date = readle(io_b, UInt16)
        crc32 = readle(io_b, UInt32)
        c_size32 = readle(io_b, UInt32)
        u_size32 = readle(io_b, UInt32)
        name_len = readle(io_b, UInt16)
        extras_len = readle(io_b, UInt16)
        comment_len = readle(io_b, UInt16)
        disk16 = readle(io_b, UInt16)
        internal_attrs = readle(io_b, UInt16)
        external_attrs = readle(io_b, UInt32)
        offset32 = readle(io_b, UInt32)
        # ensure there is enough room for the variable sized data
        @argcheck bytesavailable(io_b) ≥ Int64(name_len) + Int64(extras_len) + Int64(comment_len)
        name_start = position(io_b) + 1
        skip(io_b, name_len)
        name_end = position(io_b)
        name_range = name_start:name_end
        #reading the variable sized extra fields
        # Parse Zip64 and check disk number is 0
        # Assume no zip64 is used, unless the extra field is found
        uncompressed_size::UInt64 = u_size32
        compressed_size::UInt64 = c_size32
        offset::UInt64 = offset32
        n_disk::UInt32 = disk16
        c_size_zip64 = false
        u_size_zip64 = false
        offset_zip64 = false
        n_disk_zip64 = false
        if !iszero(extras_len)
            extras_bytes_left::Int = extras_len
            # local p::Int = 1
            while extras_bytes_left ≥ 4
                local id = readle(io_b, UInt16)
                local data_size::Int = readle(io_b, UInt16)
                local data_size_left::Int = data_size
                extras_bytes_left -= 4
                @argcheck data_size ≤ extras_bytes_left
                if id == 0x0001 && version_needed ≥ 45
                    if u_size32 == -1%UInt32 && data_size_left ≥ 8
                        uncompressed_size = readle(io_b, UInt64)
                        u_size_zip64 = true
                        data_size_left -= 8
                    end
                    if c_size32 == -1%UInt32 && data_size_left ≥ 8
                        compressed_size = readle(io_b, UInt64)
                        c_size_zip64 = true
                        data_size_left -= 8
                    end
                    if offset32 == -1%UInt32 && data_size_left ≥ 8
                        offset = readle(io_b, UInt64)
                        offset_zip64 = true
                        data_size_left -= 8
                    end
                    if disk16 == -1%UInt16 && data_size_left ≥ 4
                        n_disk = readle(io_b, UInt32)
                        @argcheck n_disk == 0
                        n_disk_zip64 = true
                        data_size_left -= 4
                    end
                end
                skip(io_b, data_size_left)
                extras_bytes_left -= data_size
            end
            skip(io_b, extras_bytes_left)
        end
        @argcheck n_disk == 0

        comment_range = if !iszero(comment_len)
            comment_start = position(io_b) + 1
            skip(io_b, comment_len)
            comment_end = position(io_b)
            comment_start:comment_end
        else
            1:0
        end
        entries[i] = EntryInfo(
            version_made::UInt8,
            os::UInt8,
            version_needed::UInt16,
            bit_flags::UInt16,
            method::UInt16,
            dos_time::UInt16,
            dos_date::UInt16,
            crc32::UInt32,
            compressed_size::UInt64,
            uncompressed_size::UInt64,
            offset::UInt64,
            c_size_zip64::Bool,
            u_size_zip64::Bool,
            offset_zip64::Bool,
            n_disk_zip64::Bool,
            internal_attrs::UInt16,
            external_attrs::UInt32,
            name_range,
            comment_range,
        )
    end
    # Maybe num_entries was too small: See https://github.com/thejoshwolfe/yauzl/issues/60
    # In that case ignore any potential extra entries.
    # Logging a warning here is not part of the zip spec, and causes JET
    # to complain.
    # Commented out warning:
    # if bytesavailable(io_b) ≥ 4
    #     if readle(io_b, UInt32) == 0x02014b50
    #         @warn "There may be some entries that are being ignored"
    #     end
    #     skip(io_b, -4)
    # end

    resize!(central_dir_buffer, position(io_b))
    entries
end


#=
Throw an ArgumentError if entry cannot be extracted.
=#
function validate_entry(entry::EntryInfo, fsize::Int64)
    # Check for unsupported bit flags
    @argcheck iszero(entry.bit_flags & 1<<0) "encrypted files not supported"
    @argcheck iszero(entry.bit_flags & 1<<5) "patched data not supported"
    @argcheck iszero(entry.bit_flags & 1<<6) "encrypted files not supported"
    @argcheck iszero(entry.bit_flags & 1<<13) "encrypted files not supported"
    @argcheck entry.version_needed ≤ 63
    # This allows for files to overlap, which sometimes can happen.
    min_loc_h_size::Int64 = min_local_header_size(entry)
    @argcheck min_loc_h_size > 29 
    @argcheck min_loc_h_size ≤ fsize
    @argcheck entry.compressed_size ≤ fsize - min_loc_h_size
    if entry.method == Store
        @argcheck entry.compressed_size == entry.uncompressed_size
    end
    @argcheck entry.offset ≤ (fsize - min_loc_h_size) - entry.compressed_size
    nothing
end


"""
    struct ZipReader{T<:AbstractVector{UInt8}}
    ZipReader(buffer::AbstractVector{UInt8})

View the bytes in `buffer` as a ZIP archive.

The array must not be modified while being read.

`zip_nentries(r::ZipReader)::Int` returns the
number of entries in the archive.

`zip_names(r::ZipReader)::Vector{String}` returns the names of all the entries in the archive.

The following get information about an entry in the archive:

Entries are indexed from `1:zip_nentries(r)`

1. `zip_name(r::ZipReader, i::Integer)::String`
1. `zip_uncompressed_size(r::ZipReader, i::Integer)::UInt64`

`zip_test_entry(r::ZipReader, i::Integer)::Nothing` checks if an entry is valid and has a good checksum.

`zip_openentry` and `zip_readentry` can be used to read data from an entry.

The `parent` function can be used to get the underlying buffer.

# Multi threading

The returned `ZipReader` object can safely be used from multiple threads;
however, the streams returned by `zip_openentry`
should only be accessed by one thread at a time.
"""
function ZipReader(buffer::AbstractVector{UInt8})
    io = InputBuffer(buffer)
    entries, central_dir_buffer, central_dir_offset = parse_central_directory(io)
    ZipReader{typeof(buffer)}(entries, central_dir_buffer, central_dir_offset, buffer)
end

function Base.show(io::IO, r::ZipReader)
    print(io, "ZipArchives.ZipReader(")
    show(io, r.buffer)
    print(io, ")")
end
function Base.show(io::IO, ::MIME"text/plain", r::ZipReader)
    topnames = Set{String}()
    total_size::Int128 = 0
    N = zip_nentries(r)
    for i in 1:N
        name = zip_name(r, i)
        uncomp_size = zip_uncompressed_size(r, i)
        total_size += uncomp_size
        local p = findfirst('/', name)
        push!(topnames, if isnothing(p)
            name
        else
            name[begin:p]
        end)
    end
    println(io, "$(length(r.buffer)) byte, $(N) entry $(typeof(r))")
    println(io, "total uncompressed size: $(total_size) bytes")
    lines, columns = displaysize(io)
    print_names = repr.(sort!(collect(topnames)))
    print(io, "  ")
    if length(print_names) ≤ lines - 5
        join(io, print_names, "\n  ")
    else
        join(io, [print_names[1:lines-6]; "⋮"], "\n  ")
    end
end

Base.parent(r::ZipReader) = r.buffer

"""
    zip_entry_data_offset(r::ZipReader, i::Integer)::Int64

Return the offset of the start of the compressed data for entry `i` from
the start of the buffer in `r`.

Throw an error if the local header is invalid.

See also [`zip_compression_method`](@ref) and [`zip_compressed_size`](@ref).
"""
zip_entry_data_offset(r::ZipReader, i::Integer) = zip_entry_data_offset(r, Int(i))
function zip_entry_data_offset(r::ZipReader, i::Int)::Int64
    fsize::Int64 = length(r.buffer)
    entry::EntryInfo = r.entries[i]
    compressed_size::Int64 = entry.compressed_size
    local_header_offset::Int64 = entry.offset
    name_len::Int64 = length(entry.name_range)
    method = entry.method
    validate_entry(entry, fsize)
    io = InputBuffer(r.buffer)
    chunk = getchunk(io, local_header_offset, 30 + name_len)
    # read and validate local header
    header_io = InputBuffer(chunk)
    @argcheck readle(header_io, UInt32) == 0x04034b50
    skip(header_io, 4)
    @argcheck readle(header_io, UInt16) == method
    skip(header_io, 4*4)
    local_name_len = readle(header_io, UInt16)
    @argcheck local_name_len == name_len
    extra_len = readle(header_io, UInt16)

    actual_local_header_size::Int64 = 30 + extra_len + name_len
    entry_data_offset::Int64 = local_header_offset + actual_local_header_size
    # make sure this doesn't overflow
    @argcheck entry_data_offset > local_header_offset
    @argcheck compressed_size ≤ fsize
    @argcheck entry_data_offset ≤ fsize - compressed_size

    @argcheck @view(chunk[begin+30 : end]) == view(r.central_dir_buffer, entry.name_range)

    entry_data_offset
end

function zip_openentry(r::ZipReader, i::Int)
    compressed_size::Int64 = zip_compressed_size(r, i)
    method = zip_compression_method(r, i)
    if method != Store && method != Deflate && method != Deflate64
        throw(ArgumentError("invalid compression method: $(method). Only Store(0), Deflate(8), and Deflate64(9) supported for now"))
    end
    entry_data_offset = zip_entry_data_offset(r, i)

    begin_ind::Int64 = firstindex(r.buffer)
    startidx = begin_ind + entry_data_offset
    @argcheck startidx > begin_ind
    lastidx = begin_ind + (entry_data_offset + compressed_size - 1)
    @argcheck lastidx > begin_ind
    @argcheck lastidx ≤ lastindex(r.buffer)
    @argcheck length(startidx:lastidx) == compressed_size
    
    base_io = InputBuffer(view(r.buffer, startidx:lastidx))
    if method == Store
        return base_io
    elseif method == Deflate
        return DeflateDecompressorStream(base_io)
    elseif method == Deflate64
        return Deflate64DecompressorStream(base_io)
    else
        # should throw and ArgumentError before this
        error("unreachable") 
    end
end