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

struct ZipFileReader
    entries::Vector{EntryInfo}
    ref_counter::Ref{Int}
end

function ZipFileReader(filename::AbstractString)
    io = open(filename)

end