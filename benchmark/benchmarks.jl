using BenchmarkTools
using Random
using ZipArchives

const SUITE = BenchmarkGroup()
rbench = SUITE["reading"] = BenchmarkGroup()

sink = IOBuffer()
names = String[]
ZipWriter(sink) do w
    for i in 1:2000
        local name = String(rand(UInt8('a'):UInt8('z'), 100))
        push!(names, name)
        zip_writefile(w, name, rand(UInt8, 10000))
    end
end
data = take!(sink)
r = ZipReader(data)

rbench["ZipReader"] = @benchmarkable ZipReader($(data))
rbench["zip_findlast_entry nothing"] = @benchmarkable zip_findlast_entry($(r), $("abc"))
rbench["zip_findlast_entry first"] = @benchmarkable zip_findlast_entry($(r), $(names[begin]))
rbench["zip_findlast_entry last"] = @benchmarkable zip_findlast_entry($(r), $(names[end]))
rbench["zip_readentry"] = @benchmarkable zip_readentry($(r), $(1000))

# Reading empty archive
sink = IOBuffer()
ZipWriter(sink) do w
end
data = take!(sink)
rbench["empty ZipReader"] = @benchmarkable ZipReader($(data))

# Reading from a file
rfbench = rbench["file"] = BenchmarkGroup()

fname = tempname()
ZipWriter(fname) do w
    zip_newfile(w, "test/compressed.txt"; compress=true)
    write(w, "Compressed \n Data \n"^1000)
    zip_newfile(w, "test/uncompressed.txt")
    write(w, "Uncompressed Data \n"^1000)
end

# Based on DiskArrays code suggested by Fabian Gans in 
# https://discourse.julialang.org/t/struggling-to-use-mmap-with-ziparchives/129839/19
struct FileArray <: AbstractVector{UInt8}
    filename::String
    offset::Int64
    len::Int64
end
function FileArray(filename::String, offset::Int64=Int64(0))
    len = filesize(filename)
    len ≥ 0 || error("filesize of $(repr(filename)) is negative")
    offset ≥ 0 || error("offset $(offset) is negative")
    offset ≤ len || error("offset $(offset) is larger than the filesize $(len)")
    FileArray(filename, offset, len-offset)
end
Base.size(s::FileArray) = (s.len,)
function Base.getindex(s::FileArray, i::Int)::UInt8
    copyto!(zeros(UInt8, 1), Int64(1), s, Int64(i), Int64(1))[1]
end
function Base.view(s::FileArray, inds::UnitRange{Int64})::FileArray
    checkbounds(s, inds)
    FileArray(s.filename, s.offset + first(inds) - Int64(1), length(inds))
end
dest_types = if VERSION ≥ v"1.11"
    (Vector{UInt8}, Memory{UInt8},)
else
    (Vector{UInt8},)
end
for dest_type in dest_types
    @eval begin
        function Base.copyto!(dest::$dest_type, dstart::Int64, src::FileArray, sstart::Int64, n::Int64)
            iszero(n) && return dest
            n ≥ 0 || throw(ArgumentError("tried to copy n=$(n) elements, but n should be non-negative"))
            checkbounds(dest, dstart)
            checkbounds(src, sstart)
            checkbounds(dest, dstart + n - Int64(1))
            checkbounds(src, sstart + n - Int64(1))
            open(src.filename) do io
                seek(io, src.offset + sstart - Int64(1))
                nb = readbytes!(io, view(dest, range(dstart; length=n)))
                nb == n || error("short read")
            end
            return dest
        end
    end
end

r = ZipReader(FileArray(fname))
rfbench["ZipReader FileArray"] = @benchmarkable ZipReader(FileArray($(fname)))
rfbench["zip_test FileArray"] = @benchmarkable zip_test($(r))

r = ZipReader(read(fname))
rfbench["ZipReader read"] = @benchmarkable ZipReader(read($(fname)))
rfbench["zip_test read"] = @benchmarkable zip_test($(r))