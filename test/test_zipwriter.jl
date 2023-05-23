using ZipArchives
using Test

Debug = false
tmp = mktempdir()
if Debug
    println("temporary directory $tmp")
end





# This defines a vector of functions in `unzippers`
# These functions take a zipfile path and a directory path
# They extract the zipfile into the directory
include("external_unzippers.jl") 

@testset "Writer compat with $(unzipper)" for unzipper in unzippers
    for filename in readdir(tmp)
        endswith(filename, ".zip") || continue
        zippath = joinpath(tmp, filename)
        mktempdir() do tmpout
            # Unzip into an output directory
            unzipper(zippath, tmpout)
            # Read zippath with ZipFile.Reader
            # Check file names and data match
            local dir = ZipFile.Reader(zippath)
            for f in dir.files
                local name = f.name
                local extracted_path = joinpath(tmpout, name)
                @test isfile(extracted_path)
                @test read(f) == read(extracted_path)
            end
            # Check number of extracted files match
            local total_files = sum(walkdir(tmpout)) do (root, dirs, files)
                length(files)
            end
            @test length(dir.files) == total_files
            close(dir)
        end
    end
end

if !Debug
    rm(tmp, recursive=true)
end