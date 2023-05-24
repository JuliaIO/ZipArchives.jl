

mutable struct ZipWriter <: IO
    _io::IO
    _own_io::Bool
    entries::Vector{EntryInfo}
    partial_entry::Union{Nothing, EntryInfo}
    closed::Bool
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

Base.isreadable(::ZipWriter) = false

Base.iswritable(w::ZipWriter) = !isnothing(w.partial_entry)

function zip_newfile(w::ZipWriter, name::AbstractString)
    iswritable(w) && zip_commitfile(w)
    @assert !iswritable(w)
    
    
end

Base.write(w::ZipWriter, x::UInt8) = write(w, Ref(x))

function assert_writeable(w::ZipWriter)
    if !iswritable(w)
        if isopen(w)
            throw(ArgumentError("ZipWriter not writable, call zip_newfile first"))
        else
            throw(ArgumentError("ZipWriter is closed"))
        end
    end
end

function Base.unsafe_write(w::ZipWriter, p::Ptr{UInt8}, n::UInt)::Int
    iszero(n) && return 0
    (n > typemax(Int)) && throw(ArgumentError("too many bytes. Tried to write $n bytes"))
    assert_writeable(w)
    # TODO add support for compression here
    nb::UInt = unsafe_write(w._io, p, n)
    w.partial_entry.crc32 = unsafe_crc32(p, nb, w.partial_entry.crc32)
    w.partial_entry.uncompressed_size += nb
    nb
end

function Base.position(w::ZipWriter)::Int64
    assert_writeable(w)
    w.partial_entry.uncompressed_size
end

function zip_commitfile(w)
end

function write_central_dir(w)
end

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