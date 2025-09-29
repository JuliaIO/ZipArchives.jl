include("common.jl")

@testset "show methods" begin
    io = IOBuffer()
    ZipWriter(io) do w
        @test repr(w) isa String
    end
    data = take!(io)
    r = ZipReader(data)
    @test repr(r) == "ZipArchives.ZipReader($(data))"
    @test sprint(io->(show(io, MIME"text/plain"(), r))) == """
    22 byte, 0 entry ZipReader{Vector{UInt8}}
    total uncompressed size: 0 bytes
      """
    @test sprint(io->(show(IOContext(io, :displaysize => (3, 80)), MIME"text/plain"(), r))) == """
    22 byte, 0 entry ZipReader{Vector{UInt8}}
    total uncompressed size: 0 bytes
      ⋮"""

    io = IOBuffer()
    ZipWriter(io) do w
        zip_writefile(w, "test", b"data")
        zip_writefile(w, "testdir/foo", b"data")
    end
    data = take!(io)
    r = ZipReader(data)
    @test repr(r) == "ZipArchives.ZipReader($(data))"
    @test sprint(io->(show(io, MIME"text/plain"(), r))) == """
    252 byte, 2 entry ZipReader{Vector{UInt8}}
    total uncompressed size: 8 bytes
      "test"
      \"testdir/\""""
    @test sprint(io->(show(IOContext(io, :displaysize => (3, 80)), MIME"text/plain"(), r))) == """
    252 byte, 2 entry ZipReader{Vector{UInt8}}
    total uncompressed size: 8 bytes
      ⋮"""
end

