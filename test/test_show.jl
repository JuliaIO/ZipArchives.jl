using ZipArchives
using Test

@testset "show methods" begin
    io = IOBuffer()
    ZipWriter(io) do w
        @test repr(w) isa String
    end
    data = take!(io)
    r = ZipBufferReader(data)
    @test repr(r) == "ZipArchives.ZipBufferReader($(data))"
    @test sprint(io->(show(io, MIME"text/plain"(), r))) == """
    22 byte, 0 entry ZipBufferReader{Vector{UInt8}}
    total uncompressed size: 0 bytes
      """
    @test sprint(io->(show(IOContext(io, :displaysize => (3, 80)), MIME"text/plain"(), r))) == """
    22 byte, 0 entry ZipBufferReader{Vector{UInt8}}
    total uncompressed size: 0 bytes
      ⋮"""

    io = IOBuffer()
    ZipWriter(io) do w
        zip_writefile(w, "test", b"data")
        zip_writefile(w, "test/foo", b"data")
    end
    data = take!(io)
    r = ZipBufferReader(data)
    @test repr(r) == "ZipArchives.ZipBufferReader($(data))"
    @test sprint(io->(show(io, MIME"text/plain"(), r))) == """
    246 byte, 2 entry ZipBufferReader{Vector{UInt8}}
    total uncompressed size: 8 bytes
      "test"
      \"test/\""""
    @test sprint(io->(show(IOContext(io, :displaysize => (3, 80)), MIME"text/plain"(), r))) == """
    246 byte, 2 entry ZipBufferReader{Vector{UInt8}}
    total uncompressed size: 8 bytes
      ⋮"""
end

