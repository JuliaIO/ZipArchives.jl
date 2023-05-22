"""
Info about an entry in a zip file.
"""
mutable struct EntryInfo
    name::String
    compressedsize::UInt64
    uncompressedsize::UInt64
    offset::UInt64
    crc32::UInt32


end

mutable struct ZipWriter <: IO
    _io::IO
    entries::Vector{EntryInfo}
    closed::Bool
    writable::Bool
    function ZipWriter(io)
        new(io,[])
    end
end


function start_new_file(w::ZipWriter, name::AbstractString;)
    
end

function write_new_file(w::ZipWriter, name::AbstractString, data::AbstractVector{UInt8};)

close



end