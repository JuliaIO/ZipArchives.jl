include("common.jl")

@testset "DOSDateTime" begin
    @testset "default" begin
        d = DOSDateTime()
        @test d.raw === 0x0021_0000
        @test (d.year, d.month, d.day, d.hour, d.minute, d.second) == (1980, 1, 1, 0, 0, 0)
        @test DOSDateTime(1980, 1, 1) == d
        @test DOSDateTime(1980, 1, 1, 0, 0, 0) == d
    end
    @testset "bit layout" begin
        @test DOSDateTime(1980, 0, 0, 0, 0, 2).raw === UInt32(1)
        @test DOSDateTime(1980, 0, 0, 0, 1, 0).raw === UInt32(1)<<5
        @test DOSDateTime(1980, 0, 0, 1, 0, 0).raw === UInt32(1)<<11
        @test DOSDateTime(1980, 0, 1, 0, 0, 0).raw === UInt32(1)<<16
        @test DOSDateTime(1980, 1, 0, 0, 0, 0).raw === UInt32(1)<<21
        @test DOSDateTime(1981, 0, 0, 0, 0, 0).raw === UInt32(1)<<25
        @test DOSDateTime(1980+127, 15, 31, 31, 63, 63).raw === typemax(UInt32)
        @test DOSDateTime(1980, 0, 0).raw === UInt32(0)
    end
    @testset "properties" begin
        d = DOSDateTime(2024, 2, 29, 23, 59, 58)
        @test (d.year, d.month, d.day, d.hour, d.minute, d.second) == (2024, 2, 29, 23, 59, 58)
        @test d.year isa Int
        @test DOSDateTime(d.raw) == d
        @test propertynames(d) == (:year, :month, :day, :hour, :minute, :second, :raw)
        # odd seconds round down
        @test DOSDateTime(2024, 2, 29, 23, 59, 59).second == 58
    end
    @testset "no validation, only truncation" begin
        d = DOSDateTime(1980+128+5, 16+3, 32+7, 32+4, 64+9, 128+10)
        @test (d.year, d.month, d.day, d.hour, d.minute, d.second) == (1985, 3, 7, 4, 9, 10)
        @test DOSDateTime(1979, 0, 0).year == 1980+127
        @test DOSDateTime(1980, -1, 0).month == 15
        @test DOSDateTime(1980, 0, 0, 0, 0, -1).second == 62
        @test DOSDateTime(big(2000), UInt8(1), Int8(2)) == DOSDateTime(2000, 1, 2)
    end
    @testset "show" begin
        d = DOSDateTime(2024, 2, 29, 23, 59, 58)
        @test repr(d) == "DOSDateTime(2024, 2, 29, 23, 59, 58)"
        @test eval(Meta.parse(repr(d))) == d
    end
    @testset "writing" begin
        d1 = DOSDateTime(2024, 2, 29, 23, 59, 58)
        d2 = DOSDateTime(2107, 12, 31, 1, 2, 4)
        d3 = DOSDateTime(1999, 9, 9, 9, 9, 8)
        d4 = DOSDateTime(0x1234_5678)
        io = IOBuffer()
        ZipWriter(io) do w
            zip_writefile(w, "default.txt", b"default")
            @test zip_dos_datetime(w, 1) == DOSDateTime()
            zip_writefile(w, "writefile.txt", b"writefile"; dos_datetime=d1)
            zip_newfile(w, "newfile.txt"; dos_datetime=d2, compress=true)
            write(w, "newfile")
            zip_newfile(w, "empty_newfile.txt"; dos_datetime=d3)
            zip_mkdir(w, "dir"; dos_datetime=d4)
            zip_mkdir(w, "default_dir")
            @test zip_dos_datetime(w, 5) == d4
        end
        data = take!(io)
        r = ZipReader(data)
        @test zip_names(r) == ["default.txt", "writefile.txt", "newfile.txt", "empty_newfile.txt", "dir/", "default_dir/"]
        expected = [DOSDateTime(), d1, d2, d3, d4, DOSDateTime()]
        for i in 1:zip_nentries(r)
            @test zip_dos_datetime(r, i) == expected[i]
            # local header has the same time and date
            offset = r.entries[i].offset
            @test data[offset+11:offset+14] == reinterpret(UInt8, [htol(expected[i].raw)])
        end
        zip_test(r)
        # existing entries keep their date and time when appending
        io = IOBuffer(copy(data); read=true, write=true)
        zip_append_archive(io) do w
            zip_writefile(w, "appended.txt", b"appended"; dos_datetime=d1)
        end
        r = ZipReader(read(seekstart(io)))
        @test [zip_dos_datetime(r, i) for i in 1:zip_nentries(r)] == [expected; d1]
    end
end
