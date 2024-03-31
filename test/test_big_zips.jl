include("common.jl")

@testset "$N many entries" for N in [0, 1, 2^16-1, 2^16,]
    filename = tempname()
    ZipWriter(filename) do w
        for i in 1:N
            zip_writefile(w,"$i",codeunits("$(-i)"))
        end
    end
    d = mmap(filename)
    r = ZipReader(d)
    @test zip_nentries(r) == N
    for i in 1:N
        @test zip_name(r, i) == "$(i)"
        zip_openentry(r, i) do file
            @test read(file, String) == "$(-i)"
        end
    end
    finalize(d)
    rm(filename)
end

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

@testset "large offsets" begin
    filename = tempname()
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
    finalize(d)
    rm(filename)
end

@testset "large offsets and many entries" begin
    filename = tempname()
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
    finalize(d)
    rm(filename)
end