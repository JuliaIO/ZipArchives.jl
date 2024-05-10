include("common.jl")
using OffsetArrays: Origin

@testset "copy_string" begin
    # copy_string is an internal function

    a = UInt8[]
    s = ZipArchives.copy_string(a)
    @test s == ""
    @test a == UInt8[]
    push!(a, 0x61)
    @test s == ""
    s = ZipArchives.copy_string(a)
    @test s == "a"
    @test a == [0x61]

    a = UInt8[0x00]
    s = ZipArchives.copy_string(a)
    @test s == "\0"
    @test a == UInt8[0x00]
    push!(a, 0x61)
    @test s == "\0"
    s = ZipArchives.copy_string(a)
    @test s == "\0a"
    @test a == [0x00, 0x61]

    a = UInt8[0x00]
    s = ZipArchives.copy_string(a)
    @test s == "\0"
    @test a == UInt8[0x00]
    pushfirst!(a, 0x61)
    @test s == "\0"
    s = ZipArchives.copy_string(a)
    @test s == "a\0"
    @test a == [0x61, 0x00]

    a = Origin(0)([0x61,0x62,0x63])
    b = ZipArchives.copy_string(a)
    @test a == Origin(0)([0x61,0x62,0x63])
    @test b == "abc"
    a[0] = 0x62
    @test b == "abc"

    io = IOBuffer()
    write(io, [0x61,0x62,0x63])
    seekstart(io)
    a = read(io, 3)
    @test a == [0x61,0x62,0x63]
    b = reshape(a, 1, 3)
    c = reshape(b, 3)
    s = ZipArchives.copy_string(a)
    @test a == [0x61,0x62,0x63]
    @test c == [0x61,0x62,0x63]
    @test s == "abc"
    c[1] = 0x62
    @test a == [0x62,0x62,0x63]
    @test c == [0x62,0x62,0x63]
    @test s == "abc"
end