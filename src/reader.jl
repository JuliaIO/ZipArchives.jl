import Zlib_jll

"""
Info about an entry in a zip file.
"""
mutable struct EntryInfo
    name::String
    compressed_size::UInt64
    uncompressed_size::UInt64
    offset::UInt64
    crc32::UInt32


end


function unsafe_crc32(p::Ptr{UInt8}, nb::UInt, crc::UInt32)::UInt32
    ccall((:crc32_z, Zlib_jll.libz),
        Culong, (Culong, Ptr{UInt8}, Csize_t),
        crc, p, nb,
    )
end