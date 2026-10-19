"""
    struct DOSDateTime
    DOSDateTime()::DOSDateTime
    DOSDateTime(year, month, day, hour=0, minute=0, second=0)::DOSDateTime
    DOSDateTime(raw::UInt32)::DOSDateTime

An MS-DOS date and time, as stored in the "last mod file time" and
"last mod file date" fields of a zip entry.

`raw` has the same bit layout as those two fields read together as a
little endian `UInt32`:

| bits  | property             |
|:------|:---------------------|
| 0-4   | `second ÷ 2`         |
| 5-10  | `minute`             |
| 11-15 | `hour`               |
| 16-20 | `day`                |
| 21-24 | `month`              |
| 25-31 | `year - 1980`        |

`DOSDateTime()` is the default used by [`ZipWriter`](@ref): 1980-01-01 00:00:00

The constructor taking the separate fields doesn't validate them.
It just truncates each field to its bit width and packs them into `raw`.
Seconds are stored with a 2 second resolution, so odd seconds are rounded down.

The properties `year`, `month`, `day`, `hour`, `minute`, and `second` unpack
the bit fields, with the same offsets and scaling as the constructor.
The packed value is the `raw` property.
"""
struct DOSDateTime
    raw::UInt32
    DOSDateTime(raw::UInt32) = new(raw)
end
DOSDateTime() = DOSDateTime(0x0021_0000)
function DOSDateTime(
        year::Integer,
        month::Integer,
        day::Integer,
        hour::Integer=0,
        minute::Integer=0,
        second::Integer=0,
    )
    DOSDateTime(
        (((second%UInt32) >> 1)  & 0x1f)       |
        ((minute%UInt32)         & 0x3f) << 5  |
        ((hour%UInt32)           & 0x1f) << 11 |
        ((day%UInt32)            & 0x1f) << 16 |
        ((month%UInt32)          & 0x0f) << 21 |
        (((year - 1980)%UInt32)  & 0x7f) << 25
    )
end
function Base.getproperty(x::DOSDateTime, s::Symbol)
    raw = getfield(x, :raw)
    if s === :second
        Int((raw & 0x1f) << 1)
    elseif s === :minute
        Int(raw >> 5 & 0x3f)
    elseif s === :hour
        Int(raw >> 11 & 0x1f)
    elseif s === :day
        Int(raw >> 16 & 0x1f)
    elseif s === :month
        Int(raw >> 21 & 0x0f)
    elseif s === :year
        Int(raw >> 25 & 0x7f) + 1980
    else
        getfield(x, s)
    end
end
Base.propertynames(::DOSDateTime, private::Bool=false) = (:year, :month, :day, :hour, :minute, :second, :raw)
function Base.show(io::IO, x::DOSDateTime)
    print(io, DOSDateTime, "(", x.year, ", ", x.month, ", ", x.day, ", ", x.hour, ", ", x.minute, ", ", x.second, ")")
end

#=
This is an internal type.
Info about an entry in a zip file.
=#
struct EntryInfo
    version_made::UInt8
    os::UInt8
    version_needed::UInt16
    bit_flags::UInt16
    method::UInt16
    dos_datetime::DOSDateTime
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
    name_range::UnitRange{Int}
    comment_range::UnitRange{Int}
end

struct ZipReader{T<:AbstractVector{UInt8}}
    entries::Vector{EntryInfo}
    central_dir_buffer::Vector{UInt8}
    central_dir_offset::Int64
    buffer::T
end


Base.@kwdef mutable struct PartialEntry
    name::String
    comment::String = ""
    external_attrs::UInt32 = UInt32(0o0100644)<<16 # external file attributes: https://unix.stackexchange.com/questions/14705/the-zip-formats-external-file-attribute
    method::UInt16 = Store # compression method
    dos_datetime::DOSDateTime = DOSDateTime() # last mod file time and date
    force_zip64::Bool = false
    offset::UInt64
    bit_flags::UInt16 = 1<<11 # general purpose bit flag: 11 UTF-8 encoding
    crc32::UInt32 = 0
    compressed_size::UInt64 = 0
    uncompressed_size::UInt64 = 0
    local_header_size::Int64 = 50 + ncodeunits(name)
end

# Internal type to keep track of ZipWriter's underlying IO offset and error state.
# inspired by https://github.com/madler/zipflow/blob/main/zipflow.c
mutable struct WriteOffsetTracker{S<:IO} <: IO
    io::S
    bad::Bool
    offset::Int64
end

mutable struct ZipWriter{S<:IO} <: IO
    _io::WriteOffsetTracker{S}
    _own_io::Bool
    entries::Vector{EntryInfo}
    central_dir_buffer::Vector{UInt8}
    partial_entry::Union{Nothing, PartialEntry}
    closed::Bool
    force_zip64::Bool

    "If checking names, this contains all committed entry names, unmodified."
    used_names::Set{String}
    
    """
    If checking names, this contains all implicit and explicit directory paths with all trailing '/'
    removed. for example, the "/a.txt" entry name creates an explicit directory "/"
    Which will be stored here as ""

    This is because in zip land there is no concept of "root", 
    and directories are allowed to be empty strings.
    """
    used_stripped_dir_names::Set{String}
    check_names::Bool
    transcoder::Union{Nothing, NoopStream{WriteOffsetTracker{S}}, DeflateCompressorStream{WriteOffsetTracker{S}}}

    "Cached codec and compression level to avoid allocations"
    compressor_cache::Union{Nothing, Tuple{DeflateCompressor, Int}}
    function ZipWriter(io::IO;
            check_names::Bool=true,
            own_io::Bool=false,
            force_zip64::Bool=false,
            offset::Int64=Int64(0),
        )
        new{typeof(io)}(
            WriteOffsetTracker(io, false, offset),
            own_io,
            EntryInfo[],
            UInt8[],
            nothing,
            false,
            force_zip64,
            Set{String}(),
            Set{String}(),
            check_names,
            nothing,
            nothing,
        )
    end
end