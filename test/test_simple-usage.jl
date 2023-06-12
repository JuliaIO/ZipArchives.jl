using ZipArchives
using Test




@testset "Write and Read zip file IO interface" begin
    filename = tempname()
    # Open a new zip file with `ZipWriter`
    # If a file already exists at filename, it will be replaced.
    # Using the do syntax ensures the file will be closed.
    # Otherwise make sure to close the ZipWriter to finish writing the file.
    ZipWriter(filename) do w
        @test repr(w) isa String
        # Write data to "test1.txt" inside the zip archive.
        # `zip_newfile` turns w into an IO that represents a file in the archive.
        @test zip_nentries(w) == 0
        zip_newfile(w, "test1.txt")
        write(w, "I am data inside test1.txt in the zip file")

        # The entries field isn't updated until the file is committed.
        @test zip_nentries(w) == 0

        # Write an empty file.
        # After calling `newfile` there is no direct way to edit any previous files in the archive.
        zip_newfile(w, "empty.txt")
        
        #Information about the previous files are in entries
        @test zip_nentries(w) == 1
        @test zip_name(w, 1) == "test1.txt"

        # Write data to "test2.txt" inside the zip file.
        zip_newfile(w, "test2.txt")
        write(w, "I am data inside test2.txt in the zip file")
    end

    # Read a zip file with `ZipFileReader`
    ZipFileReader(filename) do r
        @test repr(r) == "ZipArchives.ZipFileReader($(repr(filename)))"
        zip_nentries(r) == 3
        @test map(i->zip_name(r, i), 1:zip_nentries(r)) == ["test1.txt", "empty.txt", "test2.txt"]
        zip_openentry(r, 1) do io
            @test read(io, String) == "I am data inside test1.txt in the zip file"
        end
    end

    # Read a zip file with `ZipBufferReader` This doesn't need to be closed.
    # It also is much faster for multithreaded reading.
    data = read(filename)
    # After passing an array to ZipBufferReader
    # make sure to never modify the array
    r = ZipBufferReader(data)
    @test repr(r) == "ZipArchives.ZipBufferReader($(data))"
    zip_nentries(r) == 3
    @test map(i->zip_name(r, i), 1:zip_nentries(r)) == ["test1.txt", "empty.txt", "test2.txt"]
    zip_openentry(r, 1) do io
        @test read(io, String) == "I am data inside test1.txt in the zip file"
    end

end
