using CodecZlib
using TranscodingStreams
using StringViews

const empty_buffer = view(UInt8[],1:0)



const ByteArray = Union{
    Base.CodeUnits{UInt8, String},
    Vector{UInt8},
    Base.FastContiguousSubArray{UInt8,1,Base.CodeUnits{UInt8,String}}, 
    Base.FastContiguousSubArray{UInt8,1,Vector{UInt8}}
}

"""
This is an internal type.
Info about an entry in a zip file.
"""
struct EntryInfo
    version_made::UInt8
    os::UInt8
    version_needed::UInt16
    bit_flags::UInt16
    method::UInt16
    dos_time::UInt16
    dos_date::UInt16
    crc32::UInt32
    compressed_size::UInt64
    uncompressed_size::UInt64
    offset::UInt64
    c_size_zip64::Bool
    u_size_zip64::Bool
    offset_zip64::Bool
    n_disk_zip64::Bool
    internal_attrs::UInt16
    external_attrs::UInt32
    name::StringView{typeof(empty_buffer)}
    comment::StringView{typeof(empty_buffer)}
end

"""
    struct ZipFileReader

Represents a zip archive file reader returned by [`zip_open_filereader`](@ref) 
"""
struct ZipFileReader
    entries::Vector{EntryInfo}
    central_dir_buffer::Vector{UInt8}
    central_dir_offset::Int64
    _io::IOStream
    _ref_counter::Base.RefValue{Int64}
    _open::Base.RefValue{Bool}
    _lock::ReentrantLock
    _fsize::Int64
    _name::String
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
    _open::Base.RefValue{Bool}
end


struct ZipBufferReader{T<:AbstractVector{UInt8}}
    entries::Vector{EntryInfo}
    central_dir_buffer::Vector{UInt8}
    central_dir_offset::Int64
    buffer::T
end


Base.@kwdef mutable struct PartialEntry{S<:IO}
    name::String
    "lowercase normalized name used to check for name collisions"
    normed_name::Union{Nothing, String}
    comment::String = ""
    external_attrs::UInt32 = UInt32(0o0100644)<<16 # external file attributes: https://unix.stackexchange.com/questions/14705/the-zip-formats-external-file-attribute
    method::UInt16 = Store # compression method
    dos_time::UInt16 = 0 # last mod file time
    dos_date::UInt16 = 0 # last mod file date
    force_zip64::Bool = false
    offset::UInt64
    bit_flags::UInt16 = 1<<11 # general purpose bit flag: 11 UTF-8 encoding
    crc32::UInt32 = 0
    compressed_size::UInt64 = 0
    uncompressed_size::UInt64 = 0
    local_header_size::Int64 = 50 + ncodeunits(name)
    transcoder::Union{Nothing, NoopStream{S}, DeflateCompressorStream{S}} = nothing
end

mutable struct ZipWriter{S<:IO} <: IO
    _io::S
    _own_io::Bool
    entries::Vector{EntryInfo}
    central_dir_buffer::Vector{UInt8}
    partial_entry::Union{Nothing, PartialEntry{S}}
    closed::Bool
    force_zip64::Bool
    used_names_lower::Set{String}
    check_names::Bool
    function ZipWriter(io::IO;
            check_names::Bool=true,
            own_io::Bool=false,
            force_zip64::Bool=false,
        )
        new{typeof(io)}(
            io,
            own_io,
            EntryInfo[],
            UInt8[],
            nothing,
            false,
            force_zip64,
            Set{String}(),
            check_names,
        )
    end
end