include("common.jl")

@testset "check_name_used unit tests" begin
    # make sure check_name_used doesn't error with random input
    for i in 1:100000
        name = String(rand(UInt8, rand(1:10)))
        ZipArchives.check_name_used(name, Set{String}(), Set{String}())
    end
    used_names = Set{String}()
    used_dirs = Set{String}()
    for i in 1:10000
        name = String(rand(UInt8, rand(1:10)))
        ZipArchives.add_name_used!(name, used_names, used_dirs)
    end
    for i in 1:1000
        name = String(rand(UInt8, rand(1:10)))
        used_names = Set{String}()
        used_dirs = Set{String}()
        ZipArchives.add_name_used!(name, used_names, used_dirs)
        @test_throws ArgumentError ZipArchives.check_name_used(name, used_names, used_dirs)
        if !endswith(name, "/")
            @test_throws ArgumentError ZipArchives.check_name_used(name*"/", used_names, used_dirs)
        end
    end

    used_names = Set{String}()
    used_dirs = Set{String}()
    ZipArchives.add_name_used!("", used_names, used_dirs)
    @test_throws ArgumentError ZipArchives.check_name_used("/a.txt", used_names, used_dirs)
    ZipArchives.check_name_used("a.txt", used_names, used_dirs)
    ZipArchives.add_name_used!("a/b/c.txt", used_names, used_dirs)
    @test_throws ArgumentError ZipArchives.check_name_used("a/b", used_names, used_dirs)
    ZipArchives.check_name_used("a/b/", used_names, used_dirs)
    ZipArchives.add_name_used!("a//c.txt", used_names, used_dirs)
    ZipArchives.check_name_used("a/c.txt", used_names, used_dirs)
end