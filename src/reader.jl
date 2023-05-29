import Zlib_jll

struct ExtraField
    id::UInt16
    data::Vector{UInt8}
end

"""
Info about an entry in a zip file.
"""
Base.@kwdef mutable struct EntryInfo
    version_made::UInt8 = 63 # version made by: zip 6.3
    os::UInt8 = UNIX
    version_needed::UInt16 = 20
    bit_flags::UInt16 = 1<<11 # general purpose bit flag: 11 UTF-8 encoding
    method::UInt16 = Store # compression method
    dos_time::UInt16 = 0 # last mod file time
    dos_date::UInt16 = 0 # last mod file date
    crc32::UInt32 = 0
    compressed_size::UInt64 = 0
    uncompressed_size::UInt64 = 0
    offset::UInt64
    c_size_zip64::Bool = false
    u_size_zip64::Bool = false
    offset_zip64::Bool = false
    n_disk_zip64::Bool = false
    internal_attrs::UInt16 = 0
    external_attrs::UInt32 = UInt32(0o0100644)<<16 # external file attributes: https://unix.stackexchange.com/questions/14705/the-zip-formats-external-file-attribute
    name::String
    comment::String = ""
    central_extras::Vector{ExtraField} = ExtraField[]
end

function Base.:(==)(x::EntryInfo, y::EntryInfo)
    iox = IOBuffer()
    write_central_header(iox, x)
    ioy = IOBuffer()
    write_central_header(ioy, y)
    take!(iox) == take!(ioy)
end


need_zip64(entry::EntryInfo)::Bool = (
    entry.u_size_zip64 ||
    entry.c_size_zip64 ||
    entry.offset_zip64 ||
    entry.n_disk_zip64
)

"""
Return the size of a typical local header for an entry.
Note, zip files in the wild may have shorter 
or longer local headers if they have a different 
amount of local extra fields.
"""
normal_local_header_size(entry::EntryInfo) = 50 + ncodeunits(entry.name)

function unsafe_crc32(p::Ptr{UInt8}, nb::UInt, crc::UInt32)::UInt32
    ccall((:crc32_z, Zlib_jll.libz),
        Culong, (Culong, Ptr{UInt8}, Csize_t),
        crc, p, nb,
    )
end

zip_nentries(x::Union{ZipFileReader,ZipWriter}) = length(x.entries)
zip_entryname(x::Union{ZipFileReader,ZipWriter}, i) = x.entries[i].name

# Copied from ZipFile.jl
readle(io::IO, ::Type{UInt64}) = htol(read(io, UInt64))
readle(io::IO, ::Type{UInt32}) = htol(read(io, UInt32))
readle(io::IO, ::Type{UInt16}) = htol(read(io, UInt16))
readle(io::IO, ::Type{UInt8}) = read(io, UInt8)


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
    parse_central_directory(io::IO)::Tuple{Vector{EntryInfo}, Int64}

Where `io` must be readable and seekable.
`io` is assumed to not be changed while this function runs.

Return the entries, and the offset in `io` of the start of the central directory as a named tuple. `(;entries, central_dir_offset)`

The central directory is after all file data.

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
    central_dir_offset::Int64, num_entries::Int64, disk::Int64 = let 
        if use_eocd64
            # Parse Zip64 end of central directory record
            # Error if not valid
            seek(io, eocd_offset - 20)
            # zip64 end of central dir locator signature
            @argcheck readle(io, UInt32) == 0x07064b50
            # number of the disk with the start of the zip64 end of central directory
            local eocd64_disk = readle(io, UInt32)
            # Only one disk is supported.
            if disk16 != -1%UInt16
                @argcheck eocd64_disk == disk16
            end
            if cd_disk16 != -1%UInt16
                @argcheck eocd64_disk == cd_disk16
            end
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
            local version_needed = readle(io, UInt16)
            @argcheck version_needed < 62
            # number of this disk
            @argcheck readle(io, UInt32) == eocd64_disk
            # number of the disk with the start of the central directory
            @argcheck readle(io, UInt32) == eocd64_disk
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
            (Int64(central_dir_offset64), Int64(num_entries64), Int64(eocd64_disk))
        else
            @argcheck disk16 == cd_disk16
            @argcheck num_entries16 == num_entries_thisdisk16
            @argcheck central_dir_offset32 ≤ eocd_offset
            (Int64(central_dir_offset32), Int64(num_entries16), Int64(disk16))
        end
    end
    seek(io, central_dir_offset)
    # parse central directory headers
    entries = EntryInfo[]
    for i in 1:num_entries
        local entry = EntryInfo(;name="", offset=0)
        # central file header signature
        @argcheck readle(io, UInt32) == 0x02014b50
        entry.version_made = readle(io, UInt8)
        entry.os = readle(io, UInt8)
        entry.version_needed = readle(io, UInt16)
        entry.bit_flags = readle(io, UInt16)
        entry.method = readle(io, UInt16)
        entry.dos_time = readle(io, UInt16)
        entry.dos_date = readle(io, UInt16)
        entry.crc32 = readle(io, UInt32)
        local c_size32 = readle(io, UInt32)
        local u_size32 = readle(io, UInt32)
        local name_len = readle(io, UInt16)
        local extras_len = readle(io, UInt16)
        local comment_len = readle(io, UInt16)
        local disk16 = readle(io, UInt16)
        entry.internal_attrs = readle(io, UInt16)
        entry.external_attrs = readle(io, UInt32)
        local offset32 = readle(io, UInt32)

        entry.name = String(read(io, name_len))
        @argcheck ncodeunits(entry.name) == name_len

        #reading the variable sized extra fields
        local central_extras = entry.central_extras
        local extras_bytes_left::Int = extras_len
        while extras_bytes_left ≥ 4
            local id = readle(io, UInt16)
            local data_size = readle(io, UInt16)
            extras_bytes_left -= 4
            @argcheck data_size ≤ extras_bytes_left
            local data = read(io, data_size)
            @argcheck length(data) == data_size
            extras_bytes_left -= data_size
            push!(central_extras, ExtraField(id, data))
        end
        @argcheck iszero(extras_bytes_left)

        if !iszero(comment_len)
            entry.comment = String(read(io, comment_len))
            @argcheck ncodeunits(entry.comment) == comment_len
        end

        # Parse Zip64 and normalize disk number to 0
        # Assume no zip64 is used, unless the extra field is found
        entry.uncompressed_size = u_size32
        entry.compressed_size = c_size32
        entry.offset = offset32
        local n_disk::UInt32 = disk16
        entry.c_size_zip64 = false
        entry.u_size_zip64 = false
        entry.offset_zip64 = false
        entry.n_disk_zip64 = false
        local zip64_idx = findfirst(x->(x.id==0x0001), central_extras)
        if !isnothing(zip64_idx) && entry.version_needed ≥ 45
            local zip64_data = central_extras[zip64_idx].data
            local b = IOBuffer(zip64_data)
            if u_size32 == -1%UInt32 && bytesavailable(b) ≥ 8
                entry.uncompressed_size = readle(b, UInt64)
                entry.u_size_zip64 = true
            end
            if c_size32 == -1%UInt32 && bytesavailable(b) ≥ 8
                entry.compressed_size = readle(b, UInt64)
                entry.c_size_zip64 = true
            end
            if offset32 == -1%UInt32 && bytesavailable(b) ≥ 8
                entry.offset = readle(b, UInt64)
                entry.offset_zip64 = true
            end
            if disk16 == -1%UInt16 && bytesavailable(b) ≥ 4
                n_disk = readle(b, UInt32)
                entry.n_disk_zip64 = true
                # normalize disk number to 0
                local n_disk_ptr = position(b) - 4
                zip64_data[(n_disk_ptr+1):(n_disk_ptr+4)] .= 0x00
            end
        end
        @argcheck n_disk == disk
        push!(entries, entry)
    end
    # Maybe num_entries was too small: See https://github.com/thejoshwolfe/yauzl/issues/60
    # In that case just log a warning
    if readle(io, UInt32) == 0x02014b50
        @warn "There may be some entries that are being ignored"
    end

    (;entries, central_dir_offset)
end

struct ZipFileReader
    entries::Vector{EntryInfo}
    central_dir_offset::Int64
    _io::IO
    _ref_counter::Ref{Int}
    _lock::ReentrantLock
end

function ZipFileReader(filename::AbstractString)
    io = open(filename)
    try # parse entries
        (;entries, central_dir_offset) = parse_central_directory(io)
        ZipFileReader(entries, central_dir_offset, io, Ref(1), ReentrantLock())
    catch # close io if there is an error parsing entries
        try
            close(io)
        finally
            throw(ArgumentError("failed to parse central directory"))
        end
    end
end