include("common.jl")
using CodecZlib: GzipCompressorStream, GzipDecompressorStream
using OffsetArrays: Origin
import Malt
import ZipFile

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
    zip_newfile(w, "test1.txt"; compress=true)
    write(w, "I am compressed data inside test1.txt in the zip file")
    zip_newfile(w, "test2.txt"; compress=true, compression_level=9)
    write(w, "I am compressed data inside test2.txt in the zip file")
    zip_newfile(w, "empty.txt"; compress=true, compression_level=9)
end

ZipWriter(joinpath(tmp, "different_compressed_levels.zip")) do w
    zip_newfile(w, "default_level.txt"; compress=true)
    write(w, "I am compressed data inside default in the zip file")
    for level in -1:9
        zip_newfile(w, "level_$(level).txt"; compress=true, compression_level=level)
        write(w, "I am compressed data inside level_$(level).txt in the zip file")
    end
    zip_newfile(w, "empty.txt"; compress=true, compression_level=9)
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
    @test !zip_name_collision(w, "test2")
    @test !zip_name_collision(w, SubString("test2", 1:2))
    @test !zip_name_collision(w, "test2.txt/")
    @test !zip_name_collision(w, "test2.txt")
    zip_commitfile(w)
    @test !zip_name_collision(w, "test2")
    @test !zip_name_collision(w, "test2.txt/")
    @test zip_name_collision(w, "test2.txt")
    @test !zip_name_collision(w, "Test2.txt")
    @test zip_name_collision(w, "🐨.txt")
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
            # Read zippath with ZipReader
            # Check file names and data match
            dir = ZipReader(read(zippath))
            for i in 1:zip_nentries(dir)
                local name = zip_name(dir, i)
                local extracted_path = joinpath(tmpout, name)
                if !isfile(extracted_path)
                    @error "$(readdir(tmpout)) doesn't contain $(repr(name))"
                    @test false
                else
                    @test zip_readentry(dir, i) == read(extracted_path)
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

if VERSION ≥ v"1.11.0" # ZipStreams requires julia 1.11
    @testset "Writer compat with ZipStreams" begin
        # setup test env for ZipStreams
        worker = Malt.Worker()
        Malt.remote_eval_fetch(worker, quote
            import Pkg
            Pkg.activate(;temp=true)
            Pkg.add(name="ZipStreams", version="3.0.0")
            import ZipStreams
            nothing
        end)
        for filename in readdir(tmp)
            endswith(filename, ".zip") || continue
            zippath = joinpath(tmp, filename)
            dir = ZipReader(read(zippath))
            Malt.remote_eval_fetch(worker, quote
                ZipStreams.zipsource($(zippath)) do zs
                    ZipStreams.is_valid!(zs) || error("archive not valid")
                end
                nothing
            end)
            Malt.remote_eval_fetch(worker, quote
                zs = ZipStreams.zipsource($(zippath))
                nothing
            end)
            for i in 1:zip_nentries(dir)
                name, data = Malt.remote_eval_fetch(worker, quote
                    f = ZipStreams.next_file(zs)
                    (ZipStreams.info(f).name, read(f,String))
                end)
                @test zip_readentry(dir, name, String) == data
            end
            @test Malt.remote_eval_fetch(worker, quote
                    f = ZipStreams.next_file(zs)
                    isnothing(f)
            end)
            Malt.remote_eval_fetch(worker, quote
                close(zs)
                nothing
            end)
        end
    end
end

if VERSION ≥ v"1.8.0" && Sys.WORD_SIZE == 64 # LibZip requires julia 1.8 and 64 bit words
    @testset "Writer compat with LibZip" begin
        # setup test env for ZipStreams
        worker = Malt.Worker()
        Malt.remote_eval_fetch(worker, quote
            import Pkg
            Pkg.activate(;temp=true)
            Pkg.add(name="LibZip", version="1.1.0")
            import LibZip
            nothing
        end)
        for filename in readdir(tmp)
            endswith(filename, ".zip") || continue
            zippath = joinpath(tmp, filename)
            dir = ZipReader(read(zippath))
            local n = zip_nentries(dir)
            @test n == Malt.remote_eval_fetch(worker, quote
                archive = LibZip.ZipArchive(read($(zippath)); flags = LibZip.LIBZIP_RDONLY | LibZip.LIBZIP_CHECKCONS)
                archive_items = collect(archive)
                length(archive_items)
            end)
            for i in 1:n
                name, data = Malt.remote_eval_fetch(worker, quote
                    String(archive_items[$(i)].name), Vector{UInt8}(archive_items[$(i)].body)
                end)
                @test zip_name(dir, i) == name
                @test zip_readentry(dir, i) == data
            end
            Malt.remote_eval_fetch(worker, quote
                close(archive)
                nothing
            end)
        end
    end
end

@testset "Writer compat with ZipFile" begin
    for filename in readdir(tmp)
        endswith(filename, ".zip") || continue
        zippath = joinpath(tmp, filename)
        dir = ZipReader(read(zippath))
        r = ZipFile.Reader(zippath)
        for f in r.files
            @test zip_readentry(dir, f.name, String) == read(f, String)
        end
        @test length(r.files) == zip_nentries(dir)
        close(r)
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
        r = ZipReader(read(filename))
        @test zip_names(r) == ["good_file"]
        zip_openentry(r, 1) do file
            @test read(file, String) == "sqrt(1.0): $(sqrt(1.0))"
        end
    end
end

@testset "writing non file entries" begin
    # Doing any of the following is not recommended,
    # and may create issues if the zip file is extracted into files.
    io = IOBuffer()
    w = ZipWriter(io; check_names=false)
    zip_mkdir(w, "empty_dir")
    @test !zip_name_collision(w, "empty_dir")
    @test zip_name_collision(w, "empty_dir/")
    @test !zip_name_collision(w, "empty_dir//")
    @test !zip_name_collision(w, "/empty_dir")
    @test !zip_name_collision(w, "/empty_Dir/")
    @test !zip_name_collision(w, "foo/empty_dir")
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
    r = ZipReader(read(io))
    @test zip_names(r) == ["empty_dir/", "symlink_entry", "script.sh", "script2.sh", "weird thing"]
    @test zip_isdir(r, 1)
    @test zip_isdir(r, "empty_dir/")
    @test zip_isdir(r, "empty_dir")
    @test zip_isdir(r, SubString("empty_dir", 1))
    @test !zip_isdir(r, "")
    @test !zip_isdir(r, "/")
    @test !zip_isexecutablefile(r, 1)
    @test zip_findlast_entry(r, "script.sh") == 3
    @test zip_findlast_entry(r, SubString("script.sh")) == 3

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
        r1 = ZipReader(out_data)
        zip_openentry(r1, 1) do entryio
            r2 = ZipReader(read(entryio))
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
        r = ZipReader(read(filename))
        @test zip_names(r) == ["inner2.txt"]
        zip_openentry(r, 1) do entryio
            @test read(entryio, String) == "inner2 text"
        end

        io = Base.Filesystem.open(filename, FLAGS, PERMISSIONS)
        ZipWriter(io; own_io=true) do w
            zip_writefile(w, "bad offset.txt", codeunits("bad offset text"))
        end
        @test_throws ArgumentError ZipReader(read(filename))

        io = Base.Filesystem.open(filename, FLAGS, PERMISSIONS)
        ZipWriter(io; own_io=true, offset=filesize(io)) do w
            zip_writefile(w, "good offset.txt", codeunits("good offset text"))
        end
        r = ZipReader(read(filename))
        @test zip_names(r) == ["good offset.txt"]

        rm(filename)
    end
    @testset "Append only IOBuffer" begin
        io = IOBuffer(;append=true)
        ZipWriter(io) do w
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
        r = ZipReader(take!(io))
        @test zip_names(r) == ["inner2.txt"]
        zip_openentry(r, 1) do entryio
            @test read(entryio, String) == "inner2 text"
        end
    end
    @testset "maxsize IOBuffer" begin
        io = IOBuffer(;maxsize=100)
        w = ZipWriter(io)
        zip_newfile(w, "inner.txt"; compress=true)
        @test_throws ArgumentError write(w, rand(UInt8, 1000000))
        @test_throws ArgumentError position(w)
        @test_throws ArgumentError write(w, rand(UInt8, 1000000))
        @test_throws ArgumentError write(w, "a"^100)
        @test_throws ArgumentError zip_newfile(w, "inner2.txt")
        @test_throws ArgumentError close(w)
        @test_throws ArgumentError ZipReader(take!(io))
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
        r = ZipReader(out_data)
        @test zip_names(r) == ["inner2.txt"]
        zip_openentry(r, 1) do entryio
            @test read(entryio, String) == "inner2 text"
        end
        rm(filename)
    end
end

@testset "writing comments" begin
    io = IOBuffer()
    ZipWriter(io) do w
        zip_newfile(w, "test1.txt"; comment="this is a comment")
        write(w, "I am data inside test1.txt in the zip file")
        zip_writefile(w, "test2.txt", b"I am data inside test2.txt in the zip file";
            comment="this is also a comment",
        )
    end
    r = ZipReader(take!(io))
    zip_test_entry(r, 1)
    zip_test_entry(r, 2)
    @test zip_comment(r, 1) == "this is a comment"
    @test zip_comment(r, 2) == "this is also a comment"
end

@testset "crc32 of offset arrays" begin
    @test zip_crc32(Origin(0)(b"hello")) == zip_crc32(b"hello")
end

@testset "crc32 of views of arrays with non Int indexes" begin
    data = rand(UInt8, 1000)
    r = zip_crc32(data[2:90])
    for T in (BigInt, UInt64, Int64, UInt32, Int32, UInt8)
        @test r == zip_crc32(view(data, T(2):T(90)))
    end
    @test zip_crc32(view(data, :)) == zip_crc32(data)
end

@testset "zip_writefile on non dense arrays" begin
    out = IOBuffer()
    ZipWriter(out) do w
        zip_writefile(w, "data.txt", 0x01:0x0f)
    end
    r = ZipReader(take!(out))
    @test zip_readentry(r, "data.txt") == 0x01:0x0f
end

if VERSION ≥ v"1.11"
    @testset "zip_writefile on memory" begin
        data = [0x41,0x42,0x43]
        a = Base.Memory{UInt8}(undef, 3)
        a .= data
        @test zip_crc32(data) == zip_crc32(a)
        out = IOBuffer()
        ZipWriter(out) do w
            zip_writefile(w, "data.txt", a)
        end
        r = ZipReader(take!(out))
        @test zip_readentry(r, "data.txt") == data
    end
    @testset "zip_writefile on view of memory" begin
        data = [0x41,0x42,0x43]
        m = Base.Memory{UInt8}(undef, 3)
        m .= data
        a = view(m, :)
        @test zip_crc32(data) == zip_crc32(a)
        out = IOBuffer()
        ZipWriter(out) do w
            zip_writefile(w, "data.txt", a)
        end
        r = ZipReader(take!(out))
        @test zip_readentry(r, "data.txt") == data
    end
end
