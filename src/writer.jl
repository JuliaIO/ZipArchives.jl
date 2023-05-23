

mutable struct ZipWriter <: IO
    _io::IO
    _own_io::Bool
    entries::Vector{EntryInfo}
    partial_entry::Union{Nothing, EntryInfo}
    closed::Bool
    mark::Int64
    function ZipWriter(io::IO; own_io::Bool=false)
        new(io, own_io, [], nothing, false, -1)
    end
end

function ZipWriter(filename::AbstractString)
    ZipWriter(Base.open(filename, "w"); own_io=true)
end

function ZipWriter(f::Function, io::IO; own_io::Bool=false)
    w = ZipWriter(io; finalize)
    try
        f(w)
    finally
        close(w)
    end
    w
end

function ZipWriter(f::Function, filename::AbstractString)
    ZipWriter(f, Base.open(filename, "w"); own_io=true)
end

Base.isopen(w::ZipWriter) = !w.closed

function Base.close(w::ZipWriter)
    if !w.closed
        try
            isnothing(w.partial_entry) || zip_commitfile(w)
        finally
            w.partial_entry = nothing
            try
                write_central_dir(w)
            finally
                @assert isnothing(w.partial_entry)
                w.closed = true
                w._own_io && close(w._io)
            end
        end
        nothing
    end
end

Base.isreadable(::ZipWriter) = false

Base.iswritable(w::ZipWriter) = !isnothing(w.partial_entry)

function zip_newfile(w::ZipWriter, name::AbstractString)

    
end

Base.write(w::ZipWriter, x::UInt8) = write(w, Ref(x))

function Base.unsafe_write(w::ZipWriter, p::Ptr{UInt8}, n::UInt)::UInt
    iszero(n) && return 0
    if !iswritable(w)
        if isopen(w)
            throw(ArgumentError("write failed, call zip_newfile first"))
        else
            throw(ArgumentError("ZipWriter is closed"))
        end
    end
    # TODO add support for compression here
    nb::UInt = unsafe_write(w._io, p, n)
    new_crc32 = unsafe_crc32(p, nb, w.partial_entry.crc32)
    # TODO what if overflow??
    new_uncompressed_size = nb + w.partial_entry.uncompressed_size
    nb
end

"""
Base.position(w::ZipWriter)::Int64
"""



end