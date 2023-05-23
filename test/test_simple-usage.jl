using ZipArchives
using Test




@testset "Write and Read zip file IO interface" begin
    filename = tempname()
    # Open a new zip file with `ZipWriter`
    # If a file already exists at filename, it will be replaced.
    # Using the do syntax ensures the file will be closed.
    # Otherwise make sure to close the ZipWriter to finish writing the file.
    ZipWriter(filename) do w
        # Write data to "test1.txt" inside the zip archive.
        # `zip_newfile` turns w into an IO that represents a file in the archive.
        @test isempty(w.entries)
        zip_newfile(w, "test1.txt")
        write(w, "I am data inside test1.txt in the zip file")

        # The entries field isn't updated until the file is committed.
        @test isempty(w.entries)

        # Write an empty file.
        # After calling `newfile` there is no direct way to edit any previous files in the archive.
        zip_newfile(w, "empty.txt")
        
        #Information about the previous files are in w.entries
        @test length(w.entries) == 1
        @test w.entries[1].name == "test1.txt"

        # Write data to "test2.txt" inside the zip file.
        zip_newfile(w, "test2.txt")
        write(w, "I am data inside test2.txt in the zip file")
    end

    # Read a zip file with `ZipReader`
    ZipReader(filename) do r
        @test map(x->x.name, r.entries) == ["test1.txt", "empty.txt", "test2.txt"]
        zip_openentry(r, 1) do io
            @test read(io, String) == "I am data inside test1.txt in the zip file"
        end
    end

end
