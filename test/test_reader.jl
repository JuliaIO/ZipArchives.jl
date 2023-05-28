using ZipArchives
using Test


@testset "find_end_of_central_directory_record unit tests" begin
    find_eocd = ZipArchives.find_end_of_central_directory_record
    io = IOBuffer(b"")
    @test_throws "io isn't a zip file. Too small" find_eocd(io)

    io = IOBuffer(b"PK\x05\x06")
    @test_throws "io isn't a zip file. Too small" find_eocd(io)

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
    @test_throws "io isn't a zip file" find_eocd(io)

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
    @test_throws "io isn't a zip file" find_eocd(io)

    io = IOBuffer("PK\x05\x06"^100)
    @test_throws "io isn't a zip file" find_eocd(io)

    io = IOBuffer("PK\x05\x06"^30000)
    @test_throws "io isn't a zip file" find_eocd(io)

    io = IOBuffer("PK\x05\x06"^30000*"ab")
    @test find_eocd(io) == 100700

    io = IOBuffer("PK\x05\x06"*"\0"^16*"\xff\xff"*"a"^(2^16-1))
    @test find_eocd(io) == 0

    io = IOBuffer("aPK\x05\x06"*"\0"^16*"\xff\xff"*"a"^(2^16-1))
    @test find_eocd(io) == 1

    io = IOBuffer("PK\x05\x06"*"\0"^16*"\xff\xff"*"a"^(2^16))
    @test_throws "io isn't a zip file" find_eocd(io)

    io = IOBuffer("PK\x05\x06"*"\0"^16*"\x00\x00"*"a"^(2^16))
    @test_throws "io isn't a zip file" find_eocd(io)


end


