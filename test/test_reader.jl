using ZipArchives
using Test
using Random

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


@testset "parse_central_directory unit tests" begin
    # Empty zip file
    io = IOBuffer([b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    (;entries, central_dir_offset) = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test iszero(central_dir_offset)

    io = IOBuffer([b"a"; b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    (;entries, central_dir_offset) = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test central_dir_offset == 0

    io = IOBuffer([b"PK\x01\x02"; b"PK\x05\x06"; zeros(UInt8,2*4+4*2+2)])
    @test_logs (:warn,"There may be some entries that are being ignored") (;entries, central_dir_offset) = ZipArchives.parse_central_directory(io)
    @test isempty(entries)
    @test central_dir_offset == 0

    # randomized tests
    for n_entries in [0:5; 0:5; [100, 2^16-1, 2^16, 2^16+1,]]
        my_rand(T::Type{<:Integer}) = rand(T)
        my_rand(T::Type{String}) = String(rand(UInt8, rand(0:2^6)))
        my_rand(T::Type{Vector{ZipArchives.ExtraField}}) = []
        in_entries = map(1:n_entries) do i
            local e = ZipArchives.EntryInfo(map(my_rand, fieldtypes(ZipArchives.EntryInfo))...)
            ZipArchives.normalize_zip64!(e, rand(Bool))
            e
        end
        # @info "created entries"
        n_padding = rand([0:20; [100, 2^16-2, 2^16-1, 2^16, 2^16+1, 2^16+2]])
        # @show n_padding
        io = IOBuffer(rand(UInt8,n_padding) ;read=true, write=true, truncate=false)
        seekend(io)
        ZipArchives.write_footer(io, in_entries; force_zip64=rand(Bool))
        # @info "wrote footer"
        (;entries, central_dir_offset) = ZipArchives.parse_central_directory(io)
        @test in_entries == entries
        @test central_dir_offset == n_padding
    end
end