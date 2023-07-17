using ZipArchives
using Test
using Random

@testset "norm_name unit tests" begin
    @test ZipArchives.norm_name("") == ""
    @test ZipArchives.norm_name("/") == "/"
    @test ZipArchives.norm_name("//") == "/"
    @test ZipArchives.norm_name("a") == "a"
    @test ZipArchives.norm_name("a/") == "a/"
    @test ZipArchives.norm_name("a//") == "a/"
    @test ZipArchives.norm_name("AaAa") == "AaAa"
    @test ZipArchives.norm_name("a/b") == "a/b"
    @test ZipArchives.norm_name("a//b") == "a/b"
    # make sure norm_name doesn't error with random input
    for i in 1:10000
        ZipArchives.norm_name(String(rand(UInt8, rand(1:10))))
    end
end