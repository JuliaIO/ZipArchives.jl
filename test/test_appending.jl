using ZipArchives
using Test

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
    data = take!(io)
    r = ZipBufferReader(data)
    @test zip_names(r) == ["testfile1.txt", "testfile2.txt", "testfile3.txt"]
    for i in 1:3
        zip_test_entry(r, i)
        zip_openentry(r, i) do file
            @test read(file, String) == "the is a file in the $i part"
        end
    end
end