using CodecZlib
using TranscodingStreams

struct ExtraField
    id::UInt16
    "Where the data for the extra field is in `central_extras_buffer`
    This doesn't include the size and id"
    data_range::UnitRange{Int}
end

const empty_extra_fields = ExtraField[]
const empty_buffer = UInt8[]

"""
This is an internal type.
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
    central_extras_buffer::Vector{UInt8} = empty_buffer
    central_extras::Vector{ExtraField} = empty_extra_fields
end

struct ZipFileReader
    entries::Vector{EntryInfo}
    central_dir_offset::Int64
    _io::IOStream
    _ref_counter::Ref{Int64}
    _open::Ref{Bool}
    _lock::ReentrantLock
    _fsize::Int64
end

"""
This is an internal type.
It reads the raw possibly compressed bytes.
It should only be exposed wrapped in a 
`TranscodingStream`
"""
mutable struct ZipFileEntryReader <: IO
    r::ZipFileReader
    p::Int64
    mark::Int64
    offset::Int64
    crc32::UInt32
    compressed_size::Int64
    _open::Ref{Bool}
end


struct ZipBufferReader{T<:AbstractVector{UInt8}}
    entries::Vector{EntryInfo}
    central_dir_offset::Int64
    buffer::T
end


struct PartialEntry
    entry::EntryInfo
    local_header_size::Int
    transcoder::Union{NoopStream, DeflateCompressorStream}
end

mutable struct ZipWriter <: IO
    _io::IO
    _own_io::Bool
    entries::Vector{EntryInfo}
    partial_entry::Union{Nothing, PartialEntry}
    closed::Bool
    force_zip64::Bool
    used_names_lower::Set{String}
    check_names::Bool
    function ZipWriter(io::IO;
            check_names::Bool=true,
            own_io::Bool=false,
            force_zip64::Bool=false,
        )
        new(
            io,
            own_io,
            EntryInfo[],
            nothing,
            false,
            force_zip64,
            Set{String}(),
            check_names,
        )
    end
end