using ZipArchives
using Base64
using Test

# These tests ensure files in the fixture can be read
function read_all(data)
    r = ZipBufferReader(data)
    result = Pair{String,String}[]
    for i in 1:zip_nentries(r)
        push!(
            result,
            zip_name(r, i) => zip_readentry(r, i, String)
        )
    end
    result
end




@testset "tests copied from go" begin
    testdata = joinpath(@__DIR__,"fixture/examples from go/testdata/")
    same_content_files = [
        "test.zip",
        "test-baddirsz.zip",
        "test-badbase.zip",
    ]
    invalid_files = [
        "test-trailing-junk.zip",
        "test-prefix.zip",
        "readme.zip",
        "readme.notzip"
    ]

    for filename in same_content_files
        # @show filename
        r = read_all(read(testdata*filename))
        @test r == [
            "test.txt" => "This is a test text file.\n",
            "gophercolor16x16.png" => read(testdata*"gophercolor16x16.png", String)
        ]
    end
    for filename in invalid_files
        @test_throws ArgumentError read_all(read(testdata*filename))
    end
    # from https://research.swtch.com/zip
    # Note: don't save this to a file to avoid virus scanner issues.
    recursive_zip = String(base64decode(read(testdata*"r.zip.b64")))
    @test read_all(codeunits(recursive_zip)) == [
        "r/r.zip" => recursive_zip
    ]
    @test read_all(read(testdata*"symlink.zip")) == [
        "symlink" => "../target"
    ]
    r = ZipBufferReader(read(testdata*"symlink.zip"))
    @test !zip_isexecutablefile(r, 1)
    @test read_all(read(testdata*"dd.zip")) == [
        "filename" => "This is a test textfile.\n",
    ]
    # created in windows XP file manager.
    @test read_all(read(testdata*"winxp.zip")) == [
        "hello" => "world \r\n",
        "dir/bar" => "foo \r\n",
        "dir/empty/" => "",
        "readonly" => "important \r\n",
    ]
    # created by Zip 3.0 under Linux
    @test read_all(read(testdata*"unix.zip")) == [
        "hello" => "world \r\n",
        "dir/bar" => "foo \r\n",
        "dir/empty/" => "",
        "readonly" => "important \r\n",
    ]
    # created by old slightly broken version of go
    @test read_all(base64decode(read(testdata*"go-no-datadesc-sig.zip.base64"))) == [
        "foo.txt" => "foo\n",
        "bar.txt" => "bar\n",
    ]
    # created by newer version of go
    @test read_all(read(testdata*"go-with-datadesc-sig.zip")) == [
        "foo.txt" => "foo\n",
        "bar.txt" => "bar\n",
    ]
    @test read_all(read(testdata*"crc32-not-streamed.zip")) == [
        "foo.txt" => "foo\n",
        "bar.txt" => "bar\n",
    ]
    @test read_all(read(testdata*"zip64.zip")) == [
        "README" => "This small file is in ZIP64 format.\n",
    ]
    # Another zip64 file with different Extras fields. (golang.org/issue/7069)
    @test read_all(read(testdata*"zip64.zip")) == [
        "README" => "This small file is in ZIP64 format.\n",
    ]
    files_with_utf8_flag = [
        "utf8-7zip.zip",
        "utf8-infozip.zip",
        "utf8-infozip.zip",
        "utf8-winrar.zip",
        "utf8-winzip.zip",
    ]
    for filename in files_with_utf8_flag
        r = ZipBufferReader(read(testdata*filename))
        @test zip_names(r) == ["世界"]
        @test zip_definitely_utf8(r, 1)
        zip_test_entry(r, 1)
    end
    r = ZipBufferReader(read(testdata*"utf8-osx.zip"))
    @test zip_names(r) == ["世界"]
    @test !zip_definitely_utf8(r, 1)
    zip_test_entry(r, 1)
    # ZipArchives currently ignores modification time.
    files_with_different_times = [
        "time-7zip.zip",
        "time-infozip.zip",
        "time-osx.zip",
        "time-win7.zip",
        "time-winrar.zip",
        "time-winzip.zip",
        "time-go.zip",
    ]
    for filename in files_with_different_times
        r = ZipBufferReader(read(testdata*filename))
        @test zip_names(r) == ["test.txt"]
        @test zip_definitely_utf8(r, 1)
        zip_test_entry(r, 1)
    end
    r = ZipBufferReader(read(testdata*"time-22738.zip"))
    @test zip_names(r) == ["file"]
    @test zip_definitely_utf8(r, 1)
    zip_test_entry(r, 1)
    @test read_all(read(testdata*"dupdir.zip")) == [
        "a/" => "",
        "a/b" => "",
        "a/b/" => "",
        "a/b/c" => "",
    ]

    # TestIssue10957
    # Verify we return ErrUnexpectedEOF when length is short.
    data = "PK\x03\x040000000PK\x01\x0200000" *
        "0000000000000000000\x00" *
        "\x00\x00\x00\x00\x00000000000000PK\x01" *
        "\x020000000000000000000" *
        "00000\v\x00\x00\x00\x00\x00000000000" *
        "00000000000000PK\x01\x0200" *
        "00000000000000000000" *
        "00\v\x00\x00\x00\x00\x00000000000000" *
        "00000000000PK\x01\x020000<" *
        "0\x00\x0000000000000000\v\x00\v" *
        "\x00\x00\x00\x00\x0000000000\x00\x00\x00\x00000" *
        "00000000PK\x01\x0200000000" *
        "0000000000000000\v\x00\x00\x00" *
        "\x00\x0000PK\x05\x06000000\x05\x00\xfd\x00\x00\x00" *
        "\v\x00\x00\x00\x00\x00"
    @test_throws ArgumentError r = ZipBufferReader(codeunits(data))

    # TestIssue10956
    # Verify that this particular malformed zip file is rejected.
    data = "PK\x06\x06PK\x06\a0000\x00\x00\x00\x00\x00\x00\x00\x00" *
        "0000PK\x05\x06000000000000" *
        "0000\v\x00000\x00\x00\x00\x00\x00\x00\x000"
    @test_throws ArgumentError r = ZipBufferReader(codeunits(data))

    # TestIssue11146
    # Verify we return ErrUnexpectedEOF when reading truncated data descriptor.
    data = "PK\x03\x040000000000000000" *
        "000000\x01\x00\x00\x000\x01\x00\x00\xff\xff0000" *
        "0000000000000000PK\x01\x02" *
        "0000\b0\b\x00000000000000" *
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x000000PK\x05\x06\x00\x00" *
        "\x00\x0000\x01\x00\x26\x00\x00\x008\x00\x00\x00\x00\x00"
    @test_throws ArgumentError r = ZipBufferReader(codeunits(data))
    
    # TestIssue12449
    # Verify we do not treat non-zip64 archives as zip64
    data = "PK\x03\x04\x14\0\b\0\0\0k\xb4\xbaF\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\x18\0\xcadUux\v\0" *
        "PK\x05\x06\0\0\0\0\x01\0\x01\0I\0\0\0D\0\0\x00111222\n" *
        "PK\a\b\x1d\x88w\xb0\a\0\0\0\a\0\0\0" *
        "PK\x01\x02\x14\x03\x14\0\b\0\0\0k\xb4\xbaF\x1d\x88w\xb0\a\0\0\0\a\0\0\0\x03\0\x18\0 \0\0\0\0\0\0\0\xa0\x81\0\0\0\0\xcadUux\v\0" *
        "PK\x05\x06\0\0\0\0\x01\0\x01\0I\0\0\0D\0\0\0\x97+I#\x05\xc5\v\xa7\xd1R\xa2\x9c" *
        "PK\x06\a\xc8\x19\xc1\xaf\x94\x9caD\xbe\x94\x19BX\x12\xc6[" *
        "PK\x05\x06\0\0\0\0\x01\0\x01\0i\0\0\0P\0\0\0\0\0"
    r = ZipBufferReader(codeunits(data))
    @test zip_names(r) == ["\xcadU"]
    @test zip_readentry(r, 1, String) == "111222\n"
    zip_test_entry(r, 1)
    @test ZipArchives.zip_comment(r, 1) == "\x97+I#\x05\xc5\v\xa7\xd1R\xa2\x9cPK\x06\a\xc8\x19\xc1\xaf\x94\x9caD\xbe\x94\x19BX\x12\xc6["

    # TestCVE202127919
    # Archive containing only the file "../test.txt"
    data =[
        0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x00,
        0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x0b, 0x00, 0x00, 0x00, 0x2e, 0x2e,
        0x2f, 0x74, 0x65, 0x73, 0x74, 0x2e, 0x74, 0x78,
        0x74, 0x0a, 0xc9, 0xc8, 0x2c, 0x56, 0xc8, 0x2c,
        0x56, 0x48, 0x54, 0x28, 0x49, 0x2d, 0x2e, 0x51,
        0x28, 0x49, 0xad, 0x28, 0x51, 0x48, 0xcb, 0xcc,
        0x49, 0xd5, 0xe3, 0x02, 0x04, 0x00, 0x00, 0xff,
        0xff, 0x50, 0x4b, 0x07, 0x08, 0xc0, 0xd7, 0xed,
        0xc3, 0x20, 0x00, 0x00, 0x00, 0x1a, 0x00, 0x00,
        0x00, 0x50, 0x4b, 0x01, 0x02, 0x14, 0x00, 0x14,
        0x00, 0x08, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xc0, 0xd7, 0xed, 0xc3, 0x20, 0x00, 0x00,
        0x00, 0x1a, 0x00, 0x00, 0x00, 0x0b, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2e,
        0x2e, 0x2f, 0x74, 0x65, 0x73, 0x74, 0x2e, 0x74,
        0x78, 0x74, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x39, 0x00,
        0x00, 0x00, 0x59, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]
    r = ZipBufferReader(data)
    @test zip_names(r) == ["../test.txt"]
    @test zip_readentry(r, 1, String) == "This is a test text file.\n"

    # TestCVE202133196
    # Archive that indicates it has 1 << 128 -1 files,
	# this would previously cause a panic due to attempting
	# to allocate a slice with 1 << 128 -1 elements.
    data = [
        0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
        0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x02,
        0x03, 0x62, 0x61, 0x65, 0x03, 0x04, 0x00, 0x00,
        0xff, 0xff, 0x50, 0x4b, 0x07, 0x08, 0xbe, 0x20,
        0x5c, 0x6c, 0x09, 0x00, 0x00, 0x00, 0x03, 0x00,
        0x00, 0x00, 0x50, 0x4b, 0x01, 0x02, 0x14, 0x00,
        0x14, 0x00, 0x08, 0x08, 0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xbe, 0x20, 0x5c, 0x6c, 0x09, 0x00,
        0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x03, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x02, 0x03, 0x50, 0x4b, 0x06, 0x06, 0x2c,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2d,
        0x00, 0x2d, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0x31, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x3a, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x50, 0x4b, 0x06, 0x07, 0x00,
        0x00, 0x00, 0x00, 0x6b, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x50,
        0x4b, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0x00, 0x00,
    ]
    @test_throws ArgumentError r = ZipBufferReader(data)

    for i in 1:3
        @test_throws ArgumentError r = ZipBufferReader(read(testdata*"fake-huge-nentries$i.badzip"))
    end

    # Also check that an archive containing a handful of empty
    # files doesn't cause an issue
    b = IOBuffer()
    ZipWriter(b; check_names=false) do w
        for i in 1:5
            zip_newfile(w,"")
        end
    end
    data = take!(b)
    r = ZipBufferReader(data)
    @test zip_nentries(r) == 5
    @test zip_names(r) == fill("", 5)

    # TestCVE202139293
    # directory size is so large, that the check in Reader.init
    # overflows when subtracting from the archive size, causing
    # the pre-allocation check to be bypassed.
    data = [
        0x50, 0x4b, 0x06, 0x06, 0x05, 0x06, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x4b,
        0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x1a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x4b,
        0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x31, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,
        0xff, 0x50, 0xfe, 0x00, 0xff, 0x00, 0x3a, 0x00, 0x00, 0x00, 0xff,
    ]
    @test_throws ArgumentError r = ZipBufferReader(data)

    # TestCVE202141772
    # Archive contains a file whose name is exclusively made up of '/', '\'
    # characters, or "../", "..\" paths, which would previously cause a panic.
    #
    #  Length   Method    Size  Cmpr    Date    Time   CRC-32   Name
    # --------  ------  ------- ---- ---------- ----- --------  ----
    #        0  Stored        0   0% 08-05-2021 18:32 00000000  /
    #        0  Stored        0   0% 09-14-2021 12:59 00000000  //
    #        0  Stored        0   0% 09-14-2021 12:59 00000000  \
    #       11  Stored       11   0% 09-14-2021 13:04 0d4a1185  /test.txt
    # --------          -------  ---                            -------
    #       11               11   0%                            4 files
    data = [
        0x50, 0x4b, 0x03, 0x04, 0x0a, 0x00, 0x00, 0x08,
        0x00, 0x00, 0x06, 0x94, 0x05, 0x53, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x2f, 0x50,
        0x4b, 0x03, 0x04, 0x0a, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x78, 0x67, 0x2e, 0x53, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x02, 0x00, 0x00, 0x00, 0x2f, 0x2f, 0x50,
        0x4b, 0x03, 0x04, 0x0a, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x78, 0x67, 0x2e, 0x53, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x5c, 0x50, 0x4b,
        0x03, 0x04, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x91, 0x68, 0x2e, 0x53, 0x85, 0x11, 0x4a, 0x0d,
        0x0b, 0x00, 0x00, 0x00, 0x0b, 0x00, 0x00, 0x00,
        0x09, 0x00, 0x00, 0x00, 0x2f, 0x74, 0x65, 0x73,
        0x74, 0x2e, 0x74, 0x78, 0x74, 0x68, 0x65, 0x6c,
        0x6c, 0x6f, 0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64,
        0x50, 0x4b, 0x01, 0x02, 0x14, 0x03, 0x0a, 0x00,
        0x00, 0x08, 0x00, 0x00, 0x06, 0x94, 0x05, 0x53,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00,
        0xed, 0x41, 0x00, 0x00, 0x00, 0x00, 0x2f, 0x50,
        0x4b, 0x01, 0x02, 0x3f, 0x00, 0x0a, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x78, 0x67, 0x2e, 0x53, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x24, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00,
        0x00, 0x1f, 0x00, 0x00, 0x00, 0x2f, 0x2f, 0x0a,
        0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x18, 0x00, 0x93, 0x98, 0x25, 0x57, 0x25,
        0xa9, 0xd7, 0x01, 0x93, 0x98, 0x25, 0x57, 0x25,
        0xa9, 0xd7, 0x01, 0x93, 0x98, 0x25, 0x57, 0x25,
        0xa9, 0xd7, 0x01, 0x50, 0x4b, 0x01, 0x02, 0x3f,
        0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78,
        0x67, 0x2e, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x20, 0x00, 0x00, 0x00, 0x3f, 0x00, 0x00,
        0x00, 0x5c, 0x0a, 0x00, 0x20, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x18, 0x00, 0x93, 0x98,
        0x25, 0x57, 0x25, 0xa9, 0xd7, 0x01, 0x93, 0x98,
        0x25, 0x57, 0x25, 0xa9, 0xd7, 0x01, 0x93, 0x98,
        0x25, 0x57, 0x25, 0xa9, 0xd7, 0x01, 0x50, 0x4b,
        0x01, 0x02, 0x3f, 0x00, 0x0a, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x91, 0x68, 0x2e, 0x53, 0x85, 0x11,
        0x4a, 0x0d, 0x0b, 0x00, 0x00, 0x00, 0x0b, 0x00,
        0x00, 0x00, 0x09, 0x00, 0x24, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00,
        0x5e, 0x00, 0x00, 0x00, 0x2f, 0x74, 0x65, 0x73,
        0x74, 0x2e, 0x74, 0x78, 0x74, 0x0a, 0x00, 0x20,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x18,
        0x00, 0xa9, 0x80, 0x51, 0x01, 0x26, 0xa9, 0xd7,
        0x01, 0x31, 0xd1, 0x57, 0x01, 0x26, 0xa9, 0xd7,
        0x01, 0xdf, 0x48, 0x85, 0xf9, 0x25, 0xa9, 0xd7,
        0x01, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00,
        0x00, 0x04, 0x00, 0x04, 0x00, 0x31, 0x01, 0x00,
        0x00, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]
    r = ZipBufferReader(data)
    @test read_all(data) == [
        "/" => "",
        "//" => "",
        "\\" => "",
        "/test.txt" => "hello world",
    ]
    for name in ["/", "//", "\\", "/test.txt"]
        @test_throws ArgumentError ZipArchives.basic_name_check(name)
    end

    # # TestInsecurePaths
    # b = IOBuffer()
    # ZipWriter(b; check_names=false) do w
    #     for name in ["/", "//", "\\", "/test.txt"]
    #         @test_throw ArgumentError zip_newfile(w,name)
    #     end
    # end
    # data = take!(b)
    # r = ZipBufferReader(data)
    # @test zip_nentries(r) == 5
    # @test zip_names(r) == fill("", 5)
end