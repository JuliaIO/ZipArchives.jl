using ZipArchives
using Test

Debug = false
tmp = mktempdir()
if Debug
    println("temporary directory $tmp")
end


# Write some zip files
ZipWriter(joinpath(tmp, "empty.zip")) do w
end

ZipWriter(joinpath(tmp, "emptyfile.zip")) do w
    zip_newfile(w, "empty.txt")
end

ZipWriter(joinpath(tmp, "onefile.zip")) do w
    zip_newfile(w, "test1.txt")
    write(w, "I am data inside test1.txt in the zip file")
end

ZipWriter(joinpath(tmp, "compressedfiles.zip")) do w
    zip_newfile(w, "test1.txt"; compression_method=ZipArchives.Deflate)
    write(w, "I am compressed data inside test1.txt in the zip file")
    zip_newfile(w, "test2.txt"; compression_method=ZipArchives.Deflate, compression_level=9)
    write(w, "I am compressed data inside test2.txt in the zip file")
    zip_newfile(w, "empty.txt"; compression_method=ZipArchives.Deflate, compression_level=9)
end

ZipWriter(joinpath(tmp, "twofiles.zip")) do w
    zip_newfile(w, "test1.txt")
    write(w, "I am data inside test1.txt in the zip file")
    zip_newfile(w, "test2.txt")
    write(w, "I am data inside test2.txt in the zip file")
end

ZipWriter(joinpath(tmp, "utf8.zip")) do w
    zip_newfile(w, "🐨.txt")
    write(w, "I am data inside 🐨.txt in the zip file")
    zip_newfile(w, "test2.txt")
    write(w, "I am data inside test2.txt in the zip file")
end

ZipWriter(joinpath(tmp, "3files-zip_writefile.zip")) do w
    zip_writefile(w, "test1.txt",  codeunits("I am data inside test1.txt in the zip file"))
    zip_writefile(w, "test2.txt",  codeunits("I am data inside test2.txt in the zip file"))
    zip_writefile(w, "empty.txt",  codeunits(""))
end

open(joinpath(tmp, "twofiles64.zip"); write=true) do io
    ZipWriter(io; force_zip64=true) do w
        zip_newfile(w, "test1.txt")
        write(w, "I am data inside test1.txt in the zip file")
        zip_newfile(w, "test2.txt")
        write(w, "I am data inside test2.txt in the zip file")
    end
end

open(joinpath(tmp, "4files64.zip"); write=true) do io
    ZipWriter(io; force_zip64=true) do w
        zip_newfile(w, "test1.txt")
        write(w, "I am data inside test1.txt in the zip file")
        zip_newfile(w, "empty1.txt")
        zip_newfile(w, "test2.txt")
        write(w, "I am data inside test2.txt in the zip file")
        zip_newfile(w, "empty2.txt")
    end
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
            # Read zippath with ZipFileReader
            # Check file names and data match
            ZipFileReader(zippath) do dir
                for i in 1:zip_nentries(dir)
                    local name = zip_name(dir, i)
                    local extracted_path = joinpath(tmpout, name)
                    @test isfile(extracted_path)
                    zip_test_entry(dir, i)
                    zip_openentry(dir, i) do f
                        @test read(f) == read(extracted_path)
                    end
                end
                # Check number of extracted files match
                local total_files = sum(walkdir(tmpout)) do (root, dirs, files)
                    length(files)
                end
                @test zip_nentries(dir) == total_files
            end
        end
    end
end

if !Debug
    rm(tmp, recursive=true)
end

@testset "Writer errors" begin
    @testset "writing without creating an entry" begin
        filename = tempname()
        w = ZipWriter(filename)
        @test_throws ArgumentError("ZipWriter not writable, call zip_newfile first") write(w, 0x00)
        zip_newfile(w, "test")
        @test write(w, 0x00) == 1
        close(w)
        @test_throws ArgumentError("ZipWriter is closed") write(w, 0x00)
    end
    @testset "aborting a file" begin
        filename = tempname()
        w = ZipWriter(filename)
        zip_newfile(w, "bad_file")
        write(w, "sqrt(-1.0): ")
        try
            write(w, "$(sqrt(-1.0))")
        catch
        end
        zip_abortfile(w)
        zip_newfile(w, "good_file")
        write(w, "sqrt(1.0): ")
        write(w, "$(sqrt(1.0))")
        zip_commitfile(w)
        @test zip_nentries(w) == 1
        close(w)
        ZipFileReader(filename) do r
            @test zip_names(r) == ["good_file"]
            zip_openentry(r, 1) do file
                @test read(file, String) == "sqrt(1.0): $(sqrt(1.0))"
            end
        end
    end
end

@testset "writing non file entries" begin
    # Doing any of the following is not recommended,
    # and may create issues if the zip file is extracted into files.
    io = IOBuffer()
    w = ZipWriter(io; check_names=false)
    zip_mkdir(w, "empty_dir")
    # Adding symlinks requires check_names=false
    ZipArchives.zip_symlink(w, "this is a invalid target", "symlink_entry")
    zip_writefile(w, "script.sh", codeunits("#!/bin/sh\nls\n"); executable=true)
    zip_newfile(w, "script2.sh"; executable=true)
    println(w, "#!/bin/sh")
    println(w, "echo 'hi'")
    close(w)
    r = ZipBufferReader(take!(io))
    @test zip_names(r) == ["empty_dir/", "symlink_entry", "script.sh", "script2.sh"]
    @test zip_isdir(r, 1)
    @test !zip_isexecutablefile(r, 1)

    @test !zip_isdir(r, 2)
    @test !zip_isexecutablefile(r, 2)

    @test !zip_isdir(r, 3)
    @test zip_isexecutablefile(r, 3)

    @test !zip_isdir(r, 4)
    @test zip_isexecutablefile(r, 4)
end