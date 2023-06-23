using ZipArchives
using Pkg.Artifacts
using Test
using Base64
using Random
using MutatePlainDataArray
import p7zip_jll

@testset "find_end_of_central_directory_record unit tests" begin
    find_eocd = ZipArchives.find_end_of_central_directory_record
    io = IOBuffer(b"")
    @test_throws ArgumentError("io isn't a zip file. Too small") find_eocd(io)

    io = IOBuffer(b"PK\x05\x06")
    @test_throws ArgumentError("io isn't a zip file. Too small") find_eocd(io)

    io = IOBuffer([b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    @test find_eocd(io) == 0

    io = IOBuffer([
        b"PK\x05\x06";
        b"PK\x05\x06";
        zeros(UInt8,2*4+4*2+2);
    ])
    @test find_eocd(io) == 4

    io = IOBuffer([
        b"PK\x05\x06";
        b"PK\x06\x06";
        zeros(UInt8,2*4+4*2+2);
    ])
    @test_throws ArgumentError find_eocd(io)

    io = IOBuffer([
        b"PK\x05\x06";
        b"PK\x05\x06";
        zeros(UInt8,2*4+4*2);
        [0x04, 0x00];
        b"PK\x05\x06";
    ])
    @test find_eocd(io) == 4

    io = IOBuffer([
        b"PK\x05\x06";
        zeros(UInt8,2*4+4*2);
        [0x04, 0x00];
        b"PK\x05\x06";
    ])
    @test find_eocd(io) == 0

    io = IOBuffer([
        b"PK\x05\x06";
        zeros(UInt8,2*4+4*2);
        [0x01, 0x00];
        b"a";
    ])
    @test find_eocd(io) == 0

    io = IOBuffer("PK\x05\x06"^7)
    @test_throws ArgumentError find_eocd(io)

    io = IOBuffer("PK\x05\x06"^100)
    @test_throws ArgumentError find_eocd(io)

    io = IOBuffer("PK\x05\x06"^30000)
    @test_throws ArgumentError find_eocd(io)

    io = IOBuffer("PK\x05\x06"^30000*"ab")
    @test find_eocd(io) == 100700

    io = IOBuffer("PK\x05\x06"*"\0"^16*"\xff\xff"*"a"^(2^16-1))
    @test find_eocd(io) == 0

    io = IOBuffer("aPK\x05\x06"*"\0"^16*"\xff\xff"*"a"^(2^16-1))
    @test find_eocd(io) == 1

    io = IOBuffer("PK\x05\x06"*"\0"^16*"\xff\xff"*"a"^(2^16))
    @test_throws ArgumentError find_eocd(io)

    io = IOBuffer("PK\x05\x06"*"\0"^16*"\x00\x00"*"a"^(2^16))
    @test_throws ArgumentError find_eocd(io)


end


@testset "parse_central_directory unit tests" begin
    # Empty zip file
    io = IOBuffer([b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    entries, central_dir_buffer, central_dir_offset = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test iszero(central_dir_offset)

    io = IOBuffer([b"a"; b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    entries, central_dir_buffer, central_dir_offset = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test central_dir_offset == 0

    io = IOBuffer([b"PK\x01\x02"; b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    @test_logs (:warn,"There may be some entries that are being ignored") entries, central_dir_buffer, central_dir_offset = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test central_dir_offset == 0
end


@testset "reading invalid files" begin
    testdata = joinpath(@__DIR__,"examples from go/testdata/")
    invalid_file = testdata*"test-trailing-junk.zip"
    filename = tempname()
    cp(invalid_file, filename)
    data = read(filename)
    @test_throws ArgumentError ZipBufferReader(data)
    @test_throws ArgumentError r = zip_open_filereader(filename)
    # zip_open_filereader will close the file if it has an error while parsing.
    # this will let the file be removed afterwards on windows.
    rm(filename)
end

@testset "reading file with unknown compression method" begin
    # The following code was used to generate the data,
    # but for some reason lzma doesn't work on github actions
    # so I am copying the results here.

    # using PyCall
    # filename = tempname()
    # zipfile = PyCall.pyimport("zipfile")
    # PyCall.@pywith zipfile.ZipFile(filename, mode="w", compression=zipfile.ZIP_LZMA) as f begin
    #     f.writestr("lzma_data", "this is the data")
    # end
    # data_b64 = base64encode(read(filename))
    data_b64 = "UEsDBD8AAgAOAHJb0FaLksVmIgAAABAAAAAJAAAAbHptYV9kYXRhCQQFAF0AAIAAADoaCWd+rnMR0beE5IbQKkMGbV//6/YgAFBLAQI/AD8AAgAOAHJb0FaLksVmIgAAABAAAAAJAAAAAAAAAAAAAACAAQAAAABsem1hX2RhdGFQSwUGAAAAAAEAAQA3AAAASQAAAAAA"
    data = base64decode(data_b64)
    filename = tempname()
    write(filename, data)
    r = ZipBufferReader(data)
    @test_throws ArgumentError("invalid compression method: 14. Only Store and Deflate supported for now") zip_test_entry(r, 1)
    @test_throws ArgumentError("invalid compression method: 14. Only Store and Deflate supported for now") zip_openentry(r, 1)
    @test zip_iscompressed(r, 1)
    @test zip_names(r) == ["lzma_data"]
    zip_open_filereader(filename) do r
        @test_throws ArgumentError("invalid compression method: 14. Only Store and Deflate supported for now") zip_test_entry(r, 1)
        @test_throws ArgumentError("invalid compression method: 14. Only Store and Deflate supported for now") zip_openentry(r, 1)
        @test zip_iscompressed(r, 1)
        @test zip_names(r) == ["lzma_data"]
    end
    rm(filename)
end

@testset "reading file with zip64 disk number" begin
    invalid_data1 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x18\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    invalid_data2 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x18\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    disk_num_ffff = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x1c\0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x18\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0N\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x8d\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0N\0\0\0?\0\0\0\0\0"
    disk_num_1 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x1c\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    disk_num_0 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x1c\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    @test_throws ArgumentError ZipBufferReader(invalid_data1)
    @test_throws ArgumentError ZipBufferReader(invalid_data2)
    @test_throws ArgumentError ZipBufferReader(disk_num_ffff)
    @test_throws ArgumentError ZipBufferReader(disk_num_1)
    r = ZipBufferReader(disk_num_0)
    @test zip_names(r) == ["test"]
    zip_test_entry(r, 1)
    @test zip_readentry(r, 1, String) == "file data"
end

@testset "opening entry after closed" begin
    testdata = joinpath(@__DIR__,"examples from go/testdata/")
    ref_file = testdata*"zip64.zip"
    filename = tempname()
    cp(ref_file, filename)
    r = zip_open_filereader(filename)
    io1 = zip_openentry(r, 1)
    close(r)
    # data can still be read after `r` is closed
    @test read(io1, String) == "This small file is in ZIP64 format.\n"
    @test eof(io1)
    @test_throws EOFError read(io1, Int)
    # but new entries cannot be opened.
    @test_throws ArgumentError("ZipFileReader is closed") io2 = zip_openentry(r, 1)
    # make sure to close all open entry readers and the ZipFileReader
    close(io1)
    @test_throws Exception read(io1, String)
    rm(filename)
end

@testset "seeking uncompressed entry" begin
    # Uncompressed entries should be seekable.
    filename = tempname()
    ZipWriter(filename) do w
        zip_writefile(w, "test.txt", b"This small file is in STORE format.\n")
    end

    r = zip_open_filereader(filename)
    io = zip_openentry(r, 1)
    close(r)
    @test !zip_iscompressed(r, 1)
    @test position(io) == 0
    @test read(io, String) == "This small file is in STORE format.\n"
    @test position(io) == 36
    @test read(io, String) == ""
    seek(io, 5)
    @test position(io) == 5
    @test read(io, String) == "small file is in STORE format.\n"
    @test position(io) == 36
    seekstart(io)
    @test position(io) == 0
    @test read(io, String) == "This small file is in STORE format.\n"
    seekstart(io)
    seekend(io)
    @test position(io) == 36
    @test eof(io)
    @test read(io, String) == ""
    close(io)
    rm(filename)
end

@testset "reading fixture" begin
    ensure_artifact_installed("fixture", joinpath(@__DIR__,"Artifacts.toml"))
    fixture_path = joinpath(artifact"fixture", "fixture")# joinpath(@__DIR__,"fixture/")
    for file in readdir(fixture_path; join=true)
        mktempdir() do tmpout
            data = read(file)
            r = ZipBufferReader(data)
            p7zip_jll.p7zip() do exe
                run(pipeline(`$(exe) x -y -o$(tmpout) $(file)`, devnull))
            end
            for i in 1:zip_nentries(r)
                zip_test_entry(r, i)
                name = zip_name(r, i)
                if zip_isdir(r, i)
                    @test isdir(joinpath(tmpout,name))
                else
                    entry_data = zip_readentry(r, i)
                    @test read(joinpath(tmpout,name)) == entry_data
                end
            end
        end
    end
end

@testset "reading corrupt entry" begin
    io = IOBuffer()
    ZipWriter(io) do w
        zip_writefile(w, "foo.txt", codeunits("KYDtLOxn"))
    end
    data = take!(io)
    # mess up file data
    data[60] = 0x03
    r = ZipBufferReader(data)
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1, String)
    # Not all zip_readentry will check the crc32
    @test zip_readentry(r, 1, Char) == 'K'
    @test zip_readentry(r, 1, Char) == 'K'

    # now try with a bad uncompressed_size
    r = ZipBufferReader(read(joinpath(artifact"fixture", "fixture", "ubuntu22-7zip.zip")))
    aref(r.entries)[1].uncompressed_size[] = 2
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1)

    # now try with a bad uncompressed_size
    r = ZipBufferReader(read(joinpath(artifact"fixture", "fixture", "ubuntu22-7zip.zip")))
    aref(r.entries)[1].uncompressed_size[] = typemax(Int64)-1
    @test_throws ArgumentError zip_test_entry(r, 1)
    # @test_throws OutOfMemoryError zip_readentry(r, 1)

    aref(r.entries)[1].uncompressed_size[] = 1<<30
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1)

end

function rewrite_zip(old::AbstractString, new::AbstractString)
    zip_open_filereader(old) do r
        ZipWriter(new) do w
            for i in 1:zip_nentries(r)
                name = zip_name(r, i)
                zip_test_entry(r, i)
                if zip_isdir(r, i)
                    zip_mkdir(w, name)
                    continue
                end
                isexe = zip_isexecutablefile(r, i)
                comp = zip_iscompressed(r, i)
                zip_writefile(w, name, zip_readentry(r, i); executable=isexe)
                # zip_newfile(w, name; executable=isexe, compress=comp)
                # zip_openentry(r, i) do io
                #     write(w, io)
                # end
                # zip_commitfile(w)
            end
        end
    end
end