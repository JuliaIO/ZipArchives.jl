using ZipArchives
using CodecZlib
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

ZipWriter(joinpath(tmp, "different_compressed_levels.zip")) do w
    zip_newfile(w, "default_level.txt"; compression_method=ZipArchives.Deflate)
    write(w, "I am compressed data inside default in the zip file")
    for level in -1:9
        zip_newfile(w, "level_$(level).txt"; compression_method=ZipArchives.Deflate, compression_level=level)
        write(w, "I am compressed data inside level_$(level).txt in the zip file")
    end
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
        @test !isreadable(w)
        @test !iswritable(w)
        @test_throws ArgumentError("ZipWriter not writable, call zip_newfile first") position(w)
        @test_throws ArgumentError("ZipWriter not writable, call zip_newfile first") write(w, 0x00)
        zip_newfile(w, "test")
        @test position(w) == 0
        @test !isreadable(w)
        @test iswritable(w)
        @test write(w, 0x00) == 1
        @test position(w) == 1
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
    # marking entry as executable.
    zip_writefile(w, "script.sh", codeunits("#!/bin/sh\nls\n"); executable=true)
    zip_newfile(w, "script2.sh"; executable=true)
    println(w, "#!/bin/sh")
    println(w, "echo 'hi'")
    zip_newfile(w, "weird thing"; executable=true, external_attrs=UInt32(0))
    close(w)
    seekstart(io)
    r = ZipBufferReader(read(io))
    @test zip_names(r) == ["empty_dir/", "symlink_entry", "script.sh", "script2.sh", "weird thing"]
    @test zip_isdir(r, 1)
    @test !zip_isexecutablefile(r, 1)

    @test !zip_isdir(r, 2)
    @test !zip_isexecutablefile(r, 2)

    @test !zip_isdir(r, 3)
    @test zip_isexecutablefile(r, 3)

    @test !zip_isdir(r, 4)
    @test zip_isexecutablefile(r, 4)

    @test !zip_isdir(r, 5)
    @test !zip_isexecutablefile(r, 5)

    w2 = zip_append_archive(io; zip_kwargs=(;check_names=true))
    @test_throws ArgumentError("symlinks in zipfiles are not very portable") ZipArchives.zip_symlink(w2, "this is a invalid target", "symlink_entry")
    close(w2)
end

@testset "writing to weird IO" begin
    @testset "recursive zip writer" begin
        # Writing to an io that isn't seekable works if only zip_writefile is used.
        # ZipWriter is not seekable.
        out = IOBuffer()
        layer1 = ZipWriter(out)
        zip_newfile(layer1, "inner.zip")
        ZipWriter(layer1) do layer2
            zip_newfile(layer2, "inner.txt")
            write(layer2, "inner most text")
            @test_throws MethodError zip_commitfile(layer2)
            @test !iswritable(layer2)
            zip_writefile(layer2, "inner2.txt", codeunits("inner2 text"))
            zip_newfile(layer2, "inner3.txt")
            write(layer2, "inner3 text")
            zip_abortfile(layer2)
        end
        close(layer1)
        out_data = take!(out)
        r1 = ZipBufferReader(out_data)
        zip_openentry(r1, 1) do entryio
            r2 = ZipBufferReader(read(entryio))
            @test zip_names(r2) == ["inner2.txt"]
            zip_openentry(r2, 1) do innerio
                @test read(innerio, String) == "inner2 text"
            end
        end
    end
    @testset "Append only file" begin
        filename = tempname()
        FLAGS = Base.Filesystem.JL_O_APPEND | Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_WRONLY
        PERMISSIONS = Base.Filesystem.S_IROTH | Base.Filesystem.S_IRGRP | Base.Filesystem.S_IWGRP | Base.Filesystem.S_IRUSR | Base.Filesystem.S_IWUSR
        io = Base.Filesystem.open(filename, FLAGS, PERMISSIONS)
        ZipWriter(io; own_io=true) do w
            zip_newfile(w, "inner.txt")
            write(w, "inner most text")
            @test_throws ArgumentError zip_commitfile(w)
            @test !iswritable(w)
            zip_writefile(w, "inner2.txt", codeunits("inner2 text"))
            zip_newfile(w, "inner3.txt")
            write(w, "inner3 text")
            zip_abortfile(w)
            zip_newfile(w, "inner4.txt")
            write(w, "inner4 text")
            @test_throws ArgumentError zip_commitfile(w)
        end
        ZipFileReader(filename) do r
            @test zip_names(r) == ["inner2.txt"]
            zip_openentry(r, 1) do entryio
                @test read(entryio, String) == "inner2 text"
            end
        end

        # To avoid this call seekend before creating the zipwriter
        # if using Base.Filesystem.open with JL_O_APPEND
        io = Base.Filesystem.open(filename, FLAGS, PERMISSIONS)
        @test_throws ArgumentError ZipWriter(io; own_io=true) do w
        end

        rm(filename)
    end
    @testset "GzipCompressorStream" begin
        filename = tempname()
        ZipWriter(GzipCompressorStream(open(filename; write=true)); own_io=true) do w
            zip_newfile(w, "inner.txt")
            write(w, "inner most text")
            @test_throws Exception zip_commitfile(w)
            @test !iswritable(w)
            zip_writefile(w, "inner2.txt", codeunits("inner2 text"))
            zip_newfile(w, "inner3.txt")
            write(w, "inner3 text")
            zip_abortfile(w)
            zip_newfile(w, "inner4.txt")
            write(w, "inner4 text")
            @test_throws Exception zip_commitfile(w)
        end
        file = GzipDecompressorStream(open(filename))
        out_data = read(file)
        close(file)
        r = ZipBufferReader(out_data)
        @test zip_names(r) == ["inner2.txt"]
        zip_openentry(r, 1) do entryio
            @test read(entryio, String) == "inner2 text"
        end
        rm(filename)
    end
end