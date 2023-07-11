import Zlib_jll

function unsafe_crc32(p::Ptr{UInt8}, nb::UInt, crc::UInt32)::UInt32
    ccall((:crc32_z, Zlib_jll.libz),
        Culong, (Culong, Ptr{UInt8}, Csize_t),
        crc, p, nb,
    )
end

const ByteArray = Union{
    Base.CodeUnits{UInt8, String},
    Vector{UInt8},
    Base.FastContiguousSubArray{UInt8,1,Base.CodeUnits{UInt8,String}}, 
    Base.FastContiguousSubArray{UInt8,1,Vector{UInt8}}
}

"""
    zip_crc32(data::AbstractVector{UInt8}, crc::UInt32=UInt32(0))::UInt32

Return the standard zip CRC32 checksum of data
"""
function zip_crc32(data::ByteArray, crc::UInt32=UInt32(0))::UInt32
    GC.@preserve data unsafe_crc32(pointer(data), UInt(length(data)), crc)
end

function zip_crc32(data::AbstractVector{UInt8}, crc::UInt32=UInt32(0))::UInt32
    zip_crc32(collect(data), crc)
end

# Copied from ZipFile.jl
readle(io::IO, ::Type{UInt64}) = htol(read(io, UInt64))
readle(io::IO, ::Type{UInt32}) = htol(read(io, UInt32))
readle(io::IO, ::Type{UInt16}) = htol(read(io, UInt16))
readle(io::IO, ::Type{UInt8}) = read(io, UInt8)


"""
Return the minimum size of a local header for an entry.
"""
min_local_header_size(entry::EntryInfo)::Int64 = 30 + length(entry.name_range)

const HasEntries = Union{ZipFileReader, ZipWriter, ZipBufferReader}

const ZipReader = Union{ZipFileReader, ZipBufferReader}


# Getters

zip_nentries(x::HasEntries)::Int = length(x.entries)
zip_name(x::HasEntries, i::Integer)::String = String(_name_view(x, i))
zip_names(x::HasEntries)::Vector{String} = String[zip_name(x,i) for i in 1:zip_nentries(x)]
zip_uncompressed_size(x::HasEntries, i::Integer)::UInt64 = x.entries[i].uncompressed_size
zip_compressed_size(x::HasEntries, i::Integer)::UInt64 = x.entries[i].compressed_size
zip_iscompressed(x::HasEntries, i::Integer)::Bool = x.entries[i].method != Store
zip_comment(x::HasEntries, i::Integer)::String = String(view(x.central_dir_buffer, x.entries[i].comment_range))
zip_stored_crc32(x::HasEntries, i::Integer)::UInt32 = x.entries[i].crc32

_name_view(x::HasEntries, i::Integer) = view(x.central_dir_buffer, x.entries[i].name_range)

"""
    zip_definitely_utf8(x::HasEntries, i::Integer)::Bool

Return true if entry `i` definitely uses utf8 encoding for the name.

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
    findlast(eachindex(x.entries)) do i
        _name_view(x, i) == data
    end
end

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
        buffer_size = 1<<12
        buffer = zeros(UInt8, buffer_size)
        GC.@preserve buffer while !eof(io)
            nb = readbytes!(io, buffer)
            @argcheck uncompressed_size < typemax(Int64)
            uncompressed_size += nb
            @argcheck uncompressed_size ≤ saved_uncompressed_size
            real_crc32 = unsafe_crc32(pointer(buffer), UInt(nb), real_crc32)
        end
        @argcheck uncompressed_size === saved_uncompressed_size
        @argcheck saved_crc32 == real_crc32
    end
    nothing
end


"""
    zip_openentry(r::ZipReader, i::Union{AbstractString, Integer})
    zip_openentry(f::Function, r::ZipReader, i::Union{AbstractString, Integer})

Open entry `i` from `r` as a readable IO.

Make sure to close this when done reading, 
if not using the do block method.

The stream returned by this function
should only be accessed by one thread at a time.

If `i` is a string open the last entry with the exact matching name.
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
    zip_readentry(r, i::Union{AbstractString, Integer}, args...; kwargs...)

Read the contents of entry `i` in `r`.

If `i` is a string read the last entry with the exact matching name.

`args...; kwargs...` are passed on to `read`
after the entry `i` in zip reader `r` is opened with [`zip_openentry`](@ref)

if `args...` are empty or `String`, this will also error if the checksum doesn't match.
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
    String(zip_readentry(r, i))
end


# If this fails, io isn't a zip file, io isn't seekable, 
# or the end of the zip file was corrupted
function find_end_of_central_directory_record(io::IO)::Int64
    seekend(io)
    fsize = position(io)
    # First assume comment is length zero
    fsize ≥ 22 || throw(ArgumentError("io isn't a zip file. Too small"))
    seek(io, fsize-22)
    b = read!(io, zeros(UInt8, 22))
    check_comment_len_valid(b, comment_len) = (
        EOCDSig == @view(b[end-21-comment_len:end-18-comment_len]) &&
        comment_len%UInt8 == b[end-1-comment_len] &&
        UInt8(comment_len>>8) == b[end-comment_len]
    )
    if check_comment_len_valid(b, 0)
        # No Zip comment fast path
        fsize-22
    else
        # There maybe is a Zip comment slow path
        fsize > 22 || throw(ArgumentError("io isn't a zip file."))
        max_comment_len::Int = min(0xFFFF, fsize-22)
        seek(io, fsize - (max_comment_len+22))
        b = read!(io, zeros(UInt8, (max_comment_len+22)))
        comment_len = 1
        while comment_len < max_comment_len && !check_comment_len_valid(b, comment_len)
            comment_len += 1
        end
        if !check_comment_len_valid(b, comment_len)
            throw(ArgumentError("""
                io isn't a zip file. 
                It may be a zip file with a corrupted ending.
                """
            ))
        end
        fsize-22-comment_len
    end
end

function check_EOCD64_used(io::IO, eocd_offset)::Bool
    # Verify that ZIP64 end of central directory is used
    # It may be that one of the values just happens to be -1
    eocd_offset ≥ 56+20 || return false
    seek(io, eocd_offset - 20)
    readle(io, UInt32) == 0x07064b50 || return false
    skip(io, 4)
    maybe_eocd64_offset = readle(io, UInt64)
    readle(io, UInt32) ≤ 1 || return false # total number of disks
    maybe_eocd64_offset ≤ eocd_offset - (56+20) || return false
    seek(io, maybe_eocd64_offset)
    readle(io, UInt32) == 0x06064b50 || return false
    return true
end

"""
    parse_central_directory(io::IO)::Tuple{Vector{EntryInfo}, Vector{UInt8}, Int64}

Where `io` must be readable and seekable.
`io` is assumed to not be changed while this function runs.

Return the entries, the raw data of the central directory, and the offset in `io` of the start of the central directory as a named tuple. `(;entries, central_dir_buffer, central_dir_offset)`

The central directory is after all entry data.

"""
function parse_central_directory(io::IO)
    # 1st find end of central dir section
    eocd_offset::Int64 = find_end_of_central_directory_record(io)
    # 2nd find where the central dir is and 
    # how many entries there are.
    # This is confusing because of ZIP64 and disk number weirdness.
    seek(io, eocd_offset+4)
    # number of this disk, or -1
    disk16 = readle(io, UInt16)
    # number of the disk with the start of the central directory or -1
    cd_disk16 = readle(io, UInt16)
    # Only one disk with num 0 is supported.
    if disk16 != -1%UInt16
        @argcheck disk16 == 0
    end
    if cd_disk16 != -1%UInt16
        @argcheck cd_disk16 == 0
    end
    # total number of entries in the central directory on this disk or -1
    num_entries_thisdisk16 = readle(io, UInt16)
    # total number of entries in the central directory or -1
    num_entries16 = readle(io, UInt16)
    # size of the central directory or -1
    skip(io, 4)
    # offset of start of central directory with respect to the starting disk number or -1
    central_dir_offset32 = readle(io, UInt32)
    maybe_eocd64 = (
        any( ==(-1%UInt16), [
            disk16,
            cd_disk16,
            num_entries_thisdisk16,
            num_entries16,
        ]) ||
        central_dir_offset32 == -1%UInt32
    )
    use_eocd64 = maybe_eocd64 && check_EOCD64_used(io, eocd_offset)
    central_dir_offset::Int64, num_entries::Int64 = let 
        if use_eocd64
            # Parse Zip64 end of central directory record
            # Error if not valid
            seek(io, eocd_offset - 20)
            # zip64 end of central dir locator signature
            @argcheck readle(io, UInt32) == 0x07064b50
            # number of the disk with the start of the zip64 end of central directory
            # Only one disk with num 0 is supported.
            @argcheck readle(io, UInt32) == 0
            local eocd64_offset = readle(io, UInt64)
            local total_num_disks = readle(io, UInt32)
            @argcheck total_num_disks ≤ 1
            seek(io, eocd64_offset)
            # zip64 end of central dir signature
            @argcheck readle(io, UInt32) == 0x06064b50
            # size of zip64 end of central directory record
            skip(io, 8)
            # version made by
            skip(io, 2)
            # version needed to extract
            # This is set to 62 if version 2 of ZIP64 is used
            # This is not supported yet.
            local version_needed = readle(io, UInt16) & 0x00FF
            @argcheck version_needed < 62
            # number of this disk
            @argcheck readle(io, UInt32) == 0
            # number of the disk with the start of the central directory
            @argcheck readle(io, UInt32) == 0
            # total number of entries in the central directory on this disk
            local num_entries_thisdisk64 = readle(io, UInt64)
            # total number of entries in the central directory
            local num_entries64 = readle(io, UInt64)
            @argcheck num_entries64 == num_entries_thisdisk64
            if num_entries16 != -1%UInt16
                @argcheck num_entries64 == num_entries16
            end
            if num_entries_thisdisk16 != -1%UInt16
                @argcheck num_entries64 == num_entries_thisdisk16
            end
            # size of the central directory
            skip(io, 8)
            # offset of start of central directory with respect to the starting disk number
            local central_dir_offset64 = readle(io, UInt64)
            if central_dir_offset32 != -1%UInt32
                @argcheck central_dir_offset64 == central_dir_offset32
            end
            @argcheck central_dir_offset64 ≤ eocd64_offset
            (Int64(central_dir_offset64), Int64(num_entries64))
        else
            @argcheck disk16 == 0
            @argcheck cd_disk16 == 0
            @argcheck num_entries16 == num_entries_thisdisk16
            @argcheck central_dir_offset32 ≤ eocd_offset
            (Int64(central_dir_offset32), Int64(num_entries16))
        end
    end
    seek(io, central_dir_offset)
    central_dir_buffer::Vector{UInt8} = read(io)
    entries = parse_central_directory_headers!(central_dir_buffer, num_entries)

    (;entries, central_dir_buffer, central_dir_offset)
end

function parse_central_directory_headers!(central_dir_buffer::Vector{UInt8}, num_entries::Int64)::Vector{EntryInfo}
    io_b = IOBuffer(central_dir_buffer)
    seekstart(io_b)
    # parse central directory headers
    # If num_entries is crazy high, avoid allocating crazy amount of memory
    @argcheck num_entries ≤ length(central_dir_buffer)>>5
    entries = Vector{EntryInfo}(undef, num_entries)
    for i in 1:num_entries
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
    # In that case just log a warning
    if bytesavailable(io_b) ≥ 4
        if readle(io_b, UInt32) == 0x02014b50
            @warn "There may be some entries that are being ignored"
        end
        skip(io_b, -4)
    end

    resize!(central_dir_buffer, position(io_b))
    entries
end

"""
    zip_open_filereader(filename::AbstractString)::ZipFileReader
    zip_open_filereader(f::Function, filename::AbstractString)

Create a reader for a zip archive in a file at path `filename`.

The file must not be modified while being read.

`zip_nentries(r::ZipFileReader)::Int` returns the 
number of entries in the archive. 

`zip_names(r::ZipFileReader)::Vector{String}` returns the names of all the entries in the archive.

The following get information about an entry in the archive:

Entries are indexed from `1:zip_nentries(r)`

1. `zip_name(r::ZipFileReader, i::Integer)::String`
1. `zip_uncompressed_size(r::ZipFileReader, i::Integer)::UInt64`

`zip_test_entry(r::ZipFileReader, i::Integer)::Nothing` 
checks if an entry is valid and has a good checksum.

Reading an entry doesn't error if the checksum is bad, so use `zip_test_entry` 
if you are worried about data corruption.

`zip_openentry` and `zip_readentry` can be used to read data from an entry.

To fully close the file, close all opened entries and the parent `ZipFileReader` object.

This will happen automatically if the do block method 
is used for `zip_open_filereader` and `zip_openentry`.

After closing the returned `ZipFileReader`, any opened entries 
will remain opened and are still readable.

# Multi threading

The returned `ZipFileReader` object can safely be used from multiple threads; 
however, the objects returned by `zip_openentry` 
should only be accessed by one thread at a time.
"""
function zip_open_filereader(filename::AbstractString)::ZipFileReader
    io_lock = ReentrantLock()
    # I'm not sure if the lock is needed in the constructor.
    io = open(filename; lock=false)
    try # parse entries
        entries, central_dir_buffer, central_dir_offset = lock(io_lock) do
            parse_central_directory(io)
        end
        _ref_counter = Ref(Int64(1))
        _open = Ref(true)
        fsize = lock(io_lock) do
            _ref_counter[] = 1
            _open[] = true
            filesize(io)
        end
        ZipFileReader(
            entries,
            central_dir_buffer,
            central_dir_offset,
            io,
            _ref_counter,
            _open,
            io_lock,
            fsize,
            filename,
        )
    catch # close io if there is an error parsing entries
        close(io)
        rethrow()
    end
end
function zip_open_filereader(f::Function, filename::AbstractString)
    r = zip_open_filereader(filename)
    try
        f(r)
    finally
        close(r)
    end
end

function Base.show(io::IO, r::ZipFileReader)
    print(io, "ZipArchives.zip_open_filereader(")
    print(io, repr(r._name))
    print(io, ")")
end


Base.isopen(r::ZipFileReader)::Bool = r._open[]

"""
Throw an ArgumentError if entry cannot be extracted.
"""
function validate_entry(entry::EntryInfo, fsize::Int64)
    if entry.method != Store && entry.method != Deflate
        throw(ArgumentError("invalid compression method: $(entry.method). Only Store and Deflate supported for now"))
    end
    # Check for unsupported bit flags
    @argcheck iszero(entry.bit_flags & 1<<0) "encrypted files not supported"
    @argcheck iszero(entry.bit_flags & 1<<5) "patched data not supported"
    @argcheck iszero(entry.bit_flags & 1<<6) "encrypted files not supported"
    @argcheck iszero(entry.bit_flags & 1<<13) "encrypted files not supported"
    @argcheck entry.version_needed ≤ 45
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

function zip_openentry(r::ZipFileReader, i::Int)::TranscodingStream
    entry::EntryInfo = r.entries[i]
    validate_entry(entry, r._fsize)
    lock(r._lock) do
        if r._open[]
            @assert r._ref_counter[] > 0 
            r._ref_counter[] += 1
        else
            throw(ArgumentError("ZipFileReader is closed"))
        end
    end
    local_header_offset::Int64 = entry.offset
    entry_data_offset::Int64 = -1
    method = entry.method
    Base.@lock r._lock begin
        # read and validate local header
        seek(r._io, local_header_offset)
        @argcheck readle(r._io, UInt32) == 0x04034b50
        skip(r._io, 4)
        @argcheck readle(r._io, UInt16) == method
        skip(r._io, 4*4)
        local_name_len = readle(r._io, UInt16)
        @argcheck local_name_len == length(entry.name_range)
        extra_len = readle(r._io, UInt16)

        actual_local_header_size::Int64 = 30 + extra_len + local_name_len
        entry_data_offset = local_header_offset + actual_local_header_size
        # make sure this doesn't overflow
        @argcheck entry_data_offset > local_header_offset
        @argcheck entry.compressed_size ≤ r._fsize
        @argcheck entry_data_offset ≤ r._fsize - entry.compressed_size

        @argcheck read(r._io, local_name_len) == view(r.central_dir_buffer, entry.name_range)
        skip(r._io, extra_len)
    end
    @argcheck entry_data_offset ≥ 0
    base_io = ZipFileEntryReader(
        r,
        0,
        -1,
        entry_data_offset,
        entry.crc32,
        entry.compressed_size,
        Ref(true),
    )
    @assert base_io.compressed_size ≥ 0
    @assert base_io.offset ≥ 0
    @assert base_io.compressed_size + base_io.offset ≥ 0
    try
        if method == Store
            return NoopStream(base_io)
        elseif method == Deflate
            return DeflateDecompressorStream(base_io)
        else
            error("unknown compression method $method. Only Deflate and Store are supported.")
        end
    catch
        close(base_io)
        rethrow()
    end
end

# Readable IO interface for ZipFileEntryReader
Base.isopen(io::ZipFileEntryReader)::Bool = io._open[]

Base.bytesavailable(io::ZipFileEntryReader)::Int64 = io.compressed_size - io.p

Base.iswritable(io::ZipFileEntryReader)::Bool = false

Base.eof(io::ZipFileEntryReader)::Bool = iszero(bytesavailable(io))

function Base.unsafe_read(io::ZipFileEntryReader, p::Ptr{UInt8}, n::UInt)::Nothing
    @argcheck isopen(io)
    n_real::UInt = min(n, bytesavailable(io))
    r = io.r
    read_start = io.offset+io.p
    @assert read_start > 0
    lock(r._lock) do
        seek(r._io, read_start)
        unsafe_read(r._io, p, n_real)
    end
    io.p += n_real
    @assert io.p ≤ io.compressed_size
    if n_real != n
        @assert eof(io)
        throw(EOFError())
    end
    nothing
end

# These functions were added to make JET happy
# They should never actually get called.
function Base.read(io::ZipFileEntryReader, ::Type{UInt8})
    error("ZipFileEntryReader does not support byte I/O")
end
function Base.unsafe_write(io::ZipFileEntryReader, p::Ptr{UInt8}, n::UInt)
    throw(ArgumentError("ZipFileEntryReader not writable"))
end

Base.position(io::ZipFileEntryReader)::Int64 = io.p

function Base.seek(io::ZipFileEntryReader, n::Integer)::ZipFileEntryReader
    @argcheck Int64(n) ∈ Int64(0):io.compressed_size
    io.p = Int64(n)
    @assert io.p ≤ io.compressed_size
    return io
end

function Base.seekend(io::ZipFileEntryReader)::ZipFileEntryReader
    io.p = io.compressed_size
    @assert io.p ≤ io.compressed_size
    return io
end

# Close will only actually close the internal io
# when all ZipFileEntryReader and ZipFileReader referencing the io
# call close.
function Base.close(io::ZipFileEntryReader)::Nothing
    if isopen(io)
        io._open[] = false
        io.p = io.compressed_size
        r = io.r
        lock(r._lock) do
            @assert r._ref_counter[] > 0 
            r._ref_counter[] -= 1
            if r._ref_counter[] == 0
                @assert !r._open[]
                close(r._io)
            end
        end
    end
    nothing
end

function Base.close(r::ZipFileReader)::Nothing
    if isopen(r)
        lock(r._lock) do
            if r._open[]
                r._open[] = false
                @assert r._ref_counter[] > 0 
                r._ref_counter[] -= 1
                if r._ref_counter[] == 0
                    close(r._io)
                end
            end
        end
    end
    nothing
end


"""
    struct ZipBufferReader{T<:AbstractVector{UInt8}}
    ZipBufferReader(buffer::AbstractVector{UInt8})

Create a reader for a zip archive in `buffer`.

The array must not be modified while being read.

`zip_nentries(r::ZipBufferReader)::Int` returns the 
number of entries in the archive. 

`zip_names(r::ZipBufferReader)::Vector{String}` returns the names of all the entries in the archive.

The following get information about an entry in the archive:

Entries are indexed from `1:zip_nentries(r)`

1. `zip_name(r::ZipBufferReader, i::Integer)::String`
1. `zip_uncompressed_size(r::ZipBufferReader, i::Integer)::UInt64`

`zip_test_entry(r::ZipBufferReader, i::Integer)::Nothing` checks if an entry is valid and has a good checksum.

Reading an entry doesn't error if the checksum is bad, so use `zip_test_entry` if you are worried about data corruption.

`zip_openentry` and `zip_readentry` can be used to read data from an entry.

A `ZipBufferReader` object does not need to be closed, and cannot be closed.

# Multi threading

The returned `ZipBufferReader` object can safely be used from multiple threads; 
however, the objects returned by `zip_openentry` 
should only be accessed by one thread at a time.
"""
function ZipBufferReader(buffer::AbstractVector{UInt8})
    io = IOBuffer(buffer)
    entries, central_dir_buffer, central_dir_offset = parse_central_directory(io)
    ZipBufferReader{typeof(buffer)}(entries, central_dir_buffer, central_dir_offset, buffer)
end

function Base.show(io::IO, r::ZipBufferReader)
    print(io, "ZipArchives.ZipBufferReader(")
    show(io, r.buffer)
    print(io, ")")
end


function zip_openentry(r::ZipBufferReader, i::Int)
    fsize::Int64 = length(r.buffer)
    entry::EntryInfo = r.entries[i]
    compressed_size::Int64 = entry.compressed_size
    validate_entry(entry, fsize)
    io = IOBuffer(r.buffer)
    local_header_offset::Int64 = entry.offset
    method = entry.method
    # read and validate local header
    seek(io, local_header_offset)
    @argcheck readle(io, UInt32) == 0x04034b50
    skip(io, 4)
    @argcheck readle(io, UInt16) == method
    skip(io, 4*4)
    local_name_len = readle(io, UInt16)
    @argcheck local_name_len == length(entry.name_range)
    extra_len = readle(io, UInt16)

    actual_local_header_size::Int64 = 30 + extra_len + local_name_len
    entry_data_offset::Int64 = local_header_offset + actual_local_header_size
    # make sure this doesn't overflow
    @argcheck entry_data_offset > local_header_offset
    @argcheck compressed_size ≤ fsize
    @argcheck entry_data_offset ≤ fsize - compressed_size

    @argcheck read(io, local_name_len) == view(r.central_dir_buffer, entry.name_range)
    skip(io, extra_len)

    begin_ind::Int64 = firstindex(r.buffer)
    startidx = begin_ind + entry_data_offset
    @argcheck startidx > begin_ind
    lastidx = begin_ind + (entry_data_offset + compressed_size - 1)
    @argcheck lastidx > begin_ind
    @argcheck lastidx ≤ lastindex(r.buffer)
    @argcheck length(startidx:lastidx) == compressed_size
    
    base_io = IOBuffer(view(r.buffer, startidx:lastidx))
    if method == Store
        return base_io
    elseif method == Deflate
        return DeflateDecompressorStream(base_io)
    else
        # validate_entry should throw and ArgumentError before this
        error("unreachable") 
    end
end