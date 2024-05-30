include("common.jl")

filenames = []
@testset "$N many entries" for N in [0, 1, 2^16-1, 2^16,]
    local filename = tempname()
    push!(filenames, filename)
    ZipWriter(filename) do w
        for i in 1:N
            zip_writefile(w,"$i",codeunits("$(-i)"))
        end
    end
    local d = mmap(filename)
    local r = ZipReader(d)
    @test zip_nentries(r) == N
    for i in 1:N
        @test zip_name(r, i) == "$(i)"
        zip_openentry(r, i) do file
            @test read(file, String) == "$(-i)"
        end
    end
end
GC.gc()
rm.(filenames)
empty!(filenames)

# The following tests need 64 bit pointers
# because they use very large zip files.
if Sys.WORD_SIZE == 64
    @testset "large uncompressed size" begin
        filename = tempname()
        ZipWriter(filename) do w
            zip_newfile(w, "bigfile";
                compress=true,
                compression_level = 1,
            )
            x = zeros(UInt8,2^17)
            for i in 1:2^16
                write(w, x)
            end
        end
        data = read(filename)
        rm(filename)
        r = ZipReader(data)
        @test zip_nentries(r) == 1
        zip_test_entry(r, 1)
    end
end

filename = tempname()
if Sys.WORD_SIZE == 64
    @testset "large offsets" begin
        ZipWriter(filename) do w
            x = rand(UInt8,2^20)
            for i in 1:2^13
                zip_writefile(w,"$i", x)
            end
        end
        d = mmap(filename)
        r = ZipReader(d)
        @test zip_nentries(r) == 2^13
        for i in 1:2^13
            @test zip_name(r, i) == "$(i)"
            zip_test_entry(r, i)
        end
    end
end
GC.gc()
rm(filename; force=true)

filename = tempname()
if Sys.WORD_SIZE == 64
    @testset "large offsets and many entries" begin
        ZipWriter(filename) do w
            x = rand(UInt8,2^17)
            for i in 1:2^16
                zip_writefile(w,"$i", x)
            end
        end
        d = mmap(filename)
        r = ZipReader(d)
        @test zip_nentries(r) == 2^16
        for i in 1:2^16
            @test zip_name(r, i) == "$(i)"
            zip_test_entry(r, i)
        end
    end
end
GC.gc()
rm(filename; force=true)