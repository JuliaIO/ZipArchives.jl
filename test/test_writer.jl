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