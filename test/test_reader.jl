include("common.jl")
using Pkg.Artifacts: @artifact_str, ensure_artifact_installed
using Base64: base64decode
using Setfield: @set
using p7zip_jll: p7zip_jll
using OffsetArrays: Origin
using SHA: sha256

@testset "parse_end_of_central_directory_record unit tests" begin
    function find_eocd(io)
        seekend(io)
        fsize = position(io)
        eocd = ZipArchives.parse_end_of_central_directory_record(io, fsize)
        fsize - 22 - eocd.comment_len
    end
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
    @test_throws ArgumentError find_eocd(io)

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

    # @test_logs (:warn,"There may be some entries that are being ignored")
    io = IOBuffer([b"PK\x01\x02"; b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    entries, central_dir_buffer, central_dir_offset = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test central_dir_offset == 0
end


@testset "reading invalid files" begin
    testdata = joinpath(@__DIR__,"examples from go/testdata/")
    invalid_file = read(testdata*"test-trailing-junk.zip")
    @test_throws ArgumentError ZipReader(invalid_file)
end

@testset "Different local name" begin
    testdata = codeunits(
    "PK\x03\x04\x14\0\0\b\0\0\0\0\0\0\xc2A\$5\x03\0\0\0\x03\0\0\0\b\0\x14\0aame.txt"*
    "\x99\x99\x10\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"*
    "abc"*
    "PK\x01\x02-\x03\x14\0\0\b\0\0\0\0\0\0\xc2A\$5\x03\0\0\0\x03\0\0\0\b\0\0\0\0\0\0\0\0\0\0\0\xa4\x81\0\0\0\0name.txt"*
    "PK\x05\x06\0\0\0\0\x01\0\x01\x006\0\0\0=\0\0\0\0\0"
    )
    r = ZipReader(testdata)
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ErrorException zip_test(r)
end

@testset "Invalid Deflated data" begin
    testdata = codeunits(
    "PK\x03\x04\x14\0\0\b\b\0\0\0\0\0\x8d\xef\x02\xd2\x03\0\0\0\x01\0\0\0\b\0\x14\0name.txt"*
    "\x99\x99\x10\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"*
    "abc"*
    "PK\x01\x02-\x03\x14\0\0\b\b\0\0\0\0\0\x8d\xef\x02\xd2\x03\0\0\0\x01\0\0\0\b\0\0\0\0\0\0\0\0\0\0\0\xa4\x81\0\0\0\0name.txt"*
    "PK\x05\x06\0\0\0\0\x01\0\x01\x006\0\0\0=\0\0\0\0\0"
    )
    r = ZipReader(testdata)
    @test_throws Exception zip_test_entry(r, 1)
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
    r = ZipReader(data)
    @test_throws ArgumentError("invalid compression method: 14. Only Store(0), Deflate(8), and Deflate64(9) supported for now") zip_test_entry(r, 1)
    @test_throws ArgumentError("invalid compression method: 14. Only Store(0), Deflate(8), and Deflate64(9) supported for now") zip_openentry(r, 1)
    @test zip_iscompressed(r, 1)
    @test zip_names(r) == ["lzma_data"]
    @test zip_compression_method(r, 1) === 0x000e
    @test zip_general_purpose_bit_flag(r, 1) === 0x0002 # indicates
    # an end-of-stream (EOS) marker is used to
    # mark the end of the compressed data stream
    entry_data_offset = 39
    compressed_size = 34
    @test zip_entry_data_offset(r, 1) === Int64(entry_data_offset)
    @test zip_entry_data_offset(r, big(1)) === Int64(entry_data_offset)
    @test zip_compressed_size(r, 1) === UInt64(compressed_size)
end

@testset "reading file with zip64 disk number" begin
    invalid_data1 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x18\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    invalid_data2 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x18\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    disk_num_ffff = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x1c\0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x18\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0N\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x8d\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0N\0\0\0?\0\0\0\0\0"
    disk_num_1 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x1c\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    disk_num_0 = b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file dataPK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x1c\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0?\0\0\0\0\0"
    @test_throws ArgumentError ZipReader(invalid_data1)
    @test_throws ArgumentError ZipReader(invalid_data2)
    @test_throws ArgumentError ZipReader(disk_num_ffff)
    @test_throws ArgumentError ZipReader(disk_num_1)
    r = ZipReader(disk_num_0)
    @test zip_names(r) == ["test"]
    zip_test_entry(r, 1)
    @test zip_readentry(r, 1, String) == "file data"

    # Test zip file from comment #1 at: https://bugs.launchpad.net/ubuntu/+source/unzip/+bug/2051952
    # See more details here: https://www.bitsgalore.org/2020/03/11/does-microsoft-onedrive-export-large-ZIP-files-that-are-corrupt
    total_disk_num_1 = codeunits("PK\x03\x04-\0\0\0\0\0\x9dBFX\xf9\x03\xff\xe8\xff\xff\xff\xff\xff\xff\xff\xff\b\x000\0test.txtUT\t\0\x0392\xc2e92\xc2eux\v\0\x01\x04\xe8\x03\0\0\x04\xe8\x03\0\0\x01\0\x10\0#\0\0\0\0\0\0\0#\0\0\0\0\0\0\0This is just an example text file.\nPK\x01\x02\x1e\x03-\0\0\0\0\0\x9dBFX\xf9\x03\xff\xe8#\0\0\0\xff\xff\xff\xff\b\0\$\0\0\0\0\0\x01\0\0\0\xb4\x81\0\0\0\0test.txtUT\x05\0\x0392\xc2eux\v\0\x01\x04\xe8\x03\0\0\x04\xe8\x03\0\0\x01\0\b\0#\0\0\0\0\0\0\0PK\x06\x06,\0\0\0\0\0\0\0\x1e\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0Z\0\0\0\0\0\0\0y\0\0\0\0\0\0\0PK\x06\a\0\0\0\0\xd3\0\0\0\0\0\0\0\0\0\0\0PK\x05\x06\0\0\0\0\x01\0\x01\0Z\0\0\0\xff\xff\xff\xff\0\0")
    r = ZipReader(total_disk_num_1)
    @test zip_names(r) == ["test.txt"]
    zip_test_entry(r, 1)
    @test zip_readentry(r, 1, String) == "This is just an example text file.\n"
end

@testset "reading file with gap between zip64 record and zip64 locator" begin
    zip_data = UInt8[
        b"PK\x03\x04-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0\x14\0test\x01\0\x10\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0file data";
        b"PK\x01\x02?\x03-\0\0\b\0\0\0\0\0\0\x13\xec\x8d_\xff\xff\xff\xff\xff\xff\xff\xff\x04\0 \0\0\0\xff\xff\0\0\0\0\xa4\x81\xff\xff\xff\xfftest\x01\0\x1c\0\t\0\0\0\0\0\0\0\t\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";
        b"PK\x06\x06,\0\0\0\0\0\0\0?\x03-\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0R\0\0\0\0\0\0\0?\0\0\0\0\0\0\0"; # Zip64 end of central directory record
        rand(UInt8, 1000000); # Junk data
        b"PK\x06\a\0\0\0\0\x91\0\0\0\0\0\0\0\x01\0\0\0"; # Zip64 end of central directory locator
        b"PK\x05\x06\0\0\0\0\x01\0\x01\0R\0\0\0\xff\xff\xff\xff\0\0"; # End of central directory record
    ]
    r = ZipReader(zip_data)
    @test zip_names(r) == ["test"]
    zip_test_entry(r, 1)
    @test zip_readentry(r, 1, String) == "file data"
end

@testset "seeking uncompressed entry" begin
    # Uncompressed entries should be seekable.
    sink = IOBuffer()
    ZipWriter(sink) do w
        zip_writefile(w, "test.txt", b"This small file is in STORE format.\n")
    end

    r = ZipReader(take!(sink))
    io = zip_openentry(r, 1)
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
end

@testset "reading fixture" begin
    ensure_artifact_installed("fixture", joinpath(@__DIR__,"Artifacts.toml"))
    fixture_path = joinpath(artifact"fixture", "fixture")# joinpath(@__DIR__,"fixture/")
    for file in readdir(fixture_path; join=true)
        mktempdir() do tmpout
            data = read(file)
            r = ZipReader(data)
            p7zip_jll.p7zip() do exe
                run(pipeline(`$(exe) x -y -o$(tmpout) $(file)`, devnull))
            end
            for i in 1:zip_nentries(r)
                zip_test_entry(r, i)
                name = zip_name(r, i)
                if zip_isdir(r, i)
                    @test isdir(joinpath(tmpout,name))
                else
                    sevenziphash = open(sha256, joinpath(tmpout,name))
                    ziphash = zip_openentry(sha256, r, i)
                    @test sevenziphash == ziphash
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
    r = ZipReader(data)
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1, String)
    # Not all zip_readentry will check the crc32
    @test zip_readentry(r, 1, Char) == 'K'
    @test zip_readentry(r, 1, Char) == 'K'

    # now try with a bad uncompressed_size
    r = ZipReader(read(joinpath(artifact"fixture", "fixture", "ubuntu22-7zip.zip")))
    correct_entry = r.entries[1]
    r.entries[1] = @set(correct_entry.uncompressed_size = 2)
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1)

    # now try with a bad uncompressed_size
    r = ZipReader(read(joinpath(artifact"fixture", "fixture", "ubuntu22-7zip.zip")))
    r.entries[1] = @set(correct_entry.uncompressed_size = typemax(Int64)-1)
    @test_throws ArgumentError zip_test_entry(r, 1)
    # @test_throws OutOfMemoryError zip_readentry(r, 1)

    r.entries[1] = @set(correct_entry.uncompressed_size = 1<<30)
    @test_throws ArgumentError zip_test_entry(r, 1)
    @test_throws ArgumentError zip_readentry(r, 1)

end

@testset "reading from view" begin
    io = IOBuffer()
    ZipWriter(io) do w
        zip_writefile(w, "foo.txt", codeunits("KYDtLOxn"))
    end
    data = take!(io)
    n = length(data)
    a = @view(zeros(UInt8, n*2)[begin:2:end])
    a .= data
    @test a == data
    r = ZipReader(a)
    @test zip_names(r) == ["foo.txt"]
    @test zip_readentry(r, 1) == codeunits("KYDtLOxn")
end

@testset "reading from offset array" begin
    io = IOBuffer()
    ZipWriter(io) do w
        zip_writefile(w, "foo.txt", codeunits("KYDtLOxn"))
    end
    data = take!(io)
    n = length(data)
    a = Origin(0)(data)
    r = ZipReader(a)
    @test zip_names(r) == ["foo.txt"]
    @test zip_readentry(r, 1) == codeunits("KYDtLOxn")
end

if VERSION ≥ v"1.11"
    @testset "reading from memory" begin
        io = IOBuffer()
        ZipWriter(io) do w
            zip_writefile(w, "foo.txt", codeunits("KYDtLOxn"))
        end
        data = take!(io)
        n = length(data)
        a = Base.Memory{UInt8}(undef, n)
        a .= data
        r = ZipReader(a)
        @test zip_names(r) == ["foo.txt"]
        @test zip_readentry(r, 1) == codeunits("KYDtLOxn")
        r = ZipReader(view(a, 1:length(a)))
        @test zip_names(r) == ["foo.txt"]
        @test zip_readentry(r, 1) == codeunits("KYDtLOxn")
    end
end

function rewrite_zip(old::AbstractString, new::AbstractString)
    d = mmap(old)
    try
        r = ZipReader(d)
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
    finally
        d=nothing; GC.gc()
    end
    d=nothing; GC.gc()
end