using ZipArchives
using Test
using Base64
using Random

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
    @test_throws ArgumentError r = ZipFileReader(filename)
    # ZipFileReader will close the file if it has an error while parsing.
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
    ZipFileReader(filename) do r
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