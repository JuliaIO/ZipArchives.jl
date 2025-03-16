using ZipArchives: 
    ZipWriter,
    zip_newfile,
    zip_writefile,
    zip_nentries,
    zip_name,
    zip_names,
    ZipReader,
    zip_openentry,
    zip_readentry,
    zip_iscompressed,
    zip_compressed_size,
    zip_uncompressed_size,
    zip_test_entry,
    zip_isdir,
    zip_isexecutablefile,
    zip_definitely_utf8

using Test: @testset, @test, @test_throws


@testset "Write and Read zip file IO interface" begin
    filename = tempname()
    # Open a new zip file with `ZipWriter`
    # If a file already exists at filename, it will be replaced.
    # Using the do syntax ensures the file will be closed.
    # Otherwise make sure to close the ZipWriter to finish writing the file.
    ZipWriter(filename) do w
        # Write data to "test/test1.txt" inside the zip archive.
        # Always use a / as a path separator even on windows.
        @test_throws ArgumentError zip_newfile(w, "test\\test1.txt")
        # `zip_newfile` turns w into an IO that represents a file in the archive.
        @test zip_nentries(w) == 0
        zip_newfile(w, "test/test1.txt")
        write(w, "I am data inside test1.txt in the zip file")

        # The current file hasn't been committed yet.
        @test zip_nentries(w) == 0

        # Write an empty file.
        # After calling `newfile` there is no direct way to edit any previous files in the archive.
        zip_newfile(w, "test/empty.txt")
        
        #Information about the previous files are in entries
        @test zip_nentries(w) == 1
        @test zip_name(w, 1) == "test/test1.txt"

        # Write data to "test2.txt" inside the zip file.
        zip_newfile(w, "test/test2.txt")
        write(w, "I am data inside test2.txt in the zip file")

        # Files can be compressed
        zip_newfile(w, "test/compressed.txt"; compress=true)
        write(w, "I am compressed text data")
    end


    # Read a zip file with `ZipReader`.
    data = read(filename)
    # `ZipReader` creates a view of `data` as an archive.
    # Don't modify `data` while reading it through a ZipReader.
    r = ZipReader(data)
    zip_nentries(r) == 3
    @test parent(r) === data

    @test zip_names(r) == ["test/test1.txt", "test/empty.txt", "test/test2.txt", "test/compressed.txt"]
    @test zip_name(r, 3) == "test/test2.txt"

    @test zip_readentry(r, 1) == codeunits("I am data inside test1.txt in the zip file")
    # zip_openentry and zip_readentry can also open the last matching entry by name.
    @test zip_readentry(r, "test/test1.txt", String) == "I am data inside test1.txt in the zip file"
    @test_throws ArgumentError("entry with name \"test1.txt\" not found") zip_readentry(r, "test1.txt", String)

    # or the equivalent with zip_openentry
    for i in (1, BigInt(1), "test/test1.txt")
        zip_openentry(r, i) do io
            @test read(io, String) == "I am data inside test1.txt in the zip file"
        end
    end

    # entries are not compressed by default
    @test !zip_iscompressed(r, 1)
    @test zip_compressed_size(r, 1) == ncodeunits("I am data inside test1.txt in the zip file")
    @test zip_compressed_size(r, 1) == zip_uncompressed_size(r, 1)

    @test zip_iscompressed(r, 4)
    @test zip_compressed_size(r, 4) != zip_uncompressed_size(r, 4)

    # Test that an entry has a correct checksum.
    zip_test_entry(r, 3)
    zip_test_entry(r, 4)
    # Test all the entries
    zip_test(r)

    # entries are not marked as executable by default
    @test !zip_isexecutablefile(r, 1)

    # entries are not marked as directories by default
    @test !zip_isdir(r, 1)
    # zip_isdir can also check if a directory is implicitly in the archive
    @test zip_isdir(r, "test")
    @test zip_isdir(r, "test/")
    @test !zip_isdir(r, "test/test1.txt")

    # entry names are marked as utf8
    @test zip_definitely_utf8(r, 1)
end