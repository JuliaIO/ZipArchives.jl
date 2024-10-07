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
