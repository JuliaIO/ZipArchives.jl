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
    central_extras::Vector{ExtraField} = []
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

# Copied from ZipFile.jl
readle(io::IO, ::Type{UInt64}) = htol(read(io, UInt64))
readle(io::IO, ::Type{UInt32}) = htol(read(io, UInt32))
readle(io::IO, ::Type{UInt16}) = htol(read(io, UInt16))

struct ZipFileReader
    entries::Vector{EntryInfo}
    _io::IO
    _ref_counter::Ref{Int}
    _lock::ReentrantLock
end

function ZipFileReader(filename::AbstractString)
    io = open(filename)
    try # parse entries
        fsize = filesize(io)
        # 1st find end of central dir section
        eocd_offset::Int64 = let 
            # First assume comment is length zero
            @argcheck fsize ≥ 22
            seek(io, fsize-22)
            local b = read(io, zeros(UInt8, 22))
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
                @argcheck fsize > 22
                local max_comment_len::Int = min(0xFFFF, fsize-22)
                seek(io, fsize - (max_comment_len+22))
                b = read(io, zeros(UInt8, (max_comment_len+22)))
                local comment_len = 1
                while comment_len ≤ max_comment_len && !check_comment_len_valid(b, comment_len)
                    comment_len += 1
                end
                @argcheck check_comment_len_valid(b, comment_len)
                fsize-22-comment_len
            end
        end
        # 2nd figure out if 
        seek(io, eocd_offset+4)
        disknum16 = readle(io, UInt16)
        cd_disk16 = readle(io, UInt16)
        num_entries_this_disk16 = readle(io, UInt16)
        num_entries16 = readle(io, UInt16)
        central_dir_size32 = readle(io, UInt32)
        central_dir_offset32 = readle(io, UInt32)








        seek()
    catch # close io if there is an error parsing entries
        try
            close(io)
        finally
            throw(ArgumentError("Failed to parse central directory"))
        end
    end

end