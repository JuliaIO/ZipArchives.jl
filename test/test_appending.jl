include("common.jl")

@testset "zip_append_archive" begin
    io = IOBuffer()
    w1 = ZipWriter(io)
    zip_newfile(w1, "testfile1.txt")
    write(w1, "the is a file in the 1 ")
    write(w1, "part")
    close(w1)
    w2 = zip_append_archive(io)
    @test zip_names(w2) == ["testfile1.txt"]
    zip_writefile(w2, "testfile2.txt", codeunits("the is a file in the 2 part"))
    close(w2)
    zip_append_archive(io) do w3
        @test zip_names(w3) == ["testfile1.txt", "testfile2.txt"]
        zip_writefile(w3, "testfile3.txt", codeunits("the is a file in the 3 part"))
    end
    # now with a file
    filename = tempname()
    seekstart(io)
    write(filename, io)
    zip_append_archive(filename) do w4
        @test zip_names(w4) == ["testfile1.txt", "testfile2.txt", "testfile3.txt"]
        zip_writefile(w4, "testfile4.txt", codeunits("the is a file in the 4 part"))
    end

    data = read(filename)
    r = ZipBufferReader(data)
    @test zip_names(r) == ["testfile$i.txt" for i in 1:4]
    for i in 1:4
        zip_test_entry(r, i)
        zip_openentry(r, i) do file
            @test read(file, String) == "the is a file in the $i part"
        end
    end
    rm(filename)
end

@testset "zip_append_archive no trunc" begin
    io = IOBuffer()
    w1 = ZipWriter(io)
    zip_writefile(w1, "testfile1.txt", codeunits("the is a file in the 1 part"))
    close(w1)
    p1 = position(io)
    w2 = zip_append_archive(io; trunc_footer=false)
    p2 = position(io)
    @test p1 == p2
    close(w2)
    p3 = position(io)
    @test p3 != p2
    w3 = zip_append_archive(io; trunc_footer=true)
    p4 = position(io)
    @test p4 == p2
    close(w3)
    @test p3 == position(io)
    r = ZipBufferReader(take!(io))
    @test zip_names(r) == ["testfile1.txt"]
    for i in 1:1
        zip_test_entry(r, i)
        zip_openentry(r, i) do file
            @test read(file, String) == "the is a file in the $i part"
        end
    end
end

@testset "zip_append_archive to a non zip file" begin
    io = IOBuffer()
    write(io, "hello world")
    @test_throws ArgumentError("io isn't a zip file. Too small") w = zip_append_archive(io)
    @test String(take!(io)) == "hello world"

    # now with a file
    filename = tempname()
    write(filename, "hello world")
    @test_throws ArgumentError("io isn't a zip file. Too small") w = zip_append_archive(filename)
    @test String(read(filename)) == "hello world"
end