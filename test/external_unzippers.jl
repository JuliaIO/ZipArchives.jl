# Used to test that zip files written by ZipArchives.jl can be read by other programs.
# This defines a vector of functions in `unzippers`
# These functions take a zipfile path and a directory path and extract the zipfile into the directory
import p7zip_jll
import LibArchive_jll
# ENV["JULIA_CONDAPKG_BACKEND"] = "Null"
try
    import PythonCall
catch
    @warn "PythonCall not working :("
end



"""
Extract the zip file at zippath into the directory dirpath
Use p7zip
"""
function unzip_p7zip(zippath, dirpath)
    # "LANG"=>"C.UTF-8" env variable is sometimes needed to get p7zip to use utf8
    # pipe output to devnull because p7zip is noisy
    # run(addenv(`$(p7zip_jll.p7zip()) x -y -o$(dirpath) $(zippath)`, "LANG"=>"C.UTF-8"))
    run(pipeline(addenv(`$(p7zip_jll.p7zip()) x -y -o$(dirpath) $(zippath)`, "LANG"=>"C.UTF-8"), devnull))
    nothing
end

"""
Extract the zip file at zippath into the directory dirpath
Use bsdtar from libarchive
"""
function unzip_bsdtar(zippath, dirpath)
    run(`$(LibArchive_jll.bsdtar()) -x -f $(zippath) -C $(dirpath)`)
    nothing
end

function have_python()
    isdefined(@__MODULE__, :PythonCall)
end

"""
Extract the zip file at zippath into the directory dirpath
Use zipfile.py from python standard library
"""
function unzip_python(zippath, dirpath)
    zipfile = PythonCall.pyimport("zipfile")
    PythonCall.pywith(zipfile.ZipFile(zippath)) do f
        test_result = PythonCall.pyconvert(Union{String, Nothing}, f.testzip())
        isnothing(test_result) || error(test_result)
        f.extractall(dirpath)
    end
    nothing
end


# This is modified to only check for `unzip` from 
# https://github.com/samoconnor/InfoZIP.jl/blob/1247b24dd3183e00baa7890c1a2c7f6766c3d774/src/InfoZIP.jl#L6-L14
function have_infozip()
    try
        occursin(r"^UnZip.*by Info-ZIP", read(`unzip`, String))
    catch
        return false
    end
end

"""
Extract the zip file at zippath into the directory dirpath
Use unzip from the infamous builtin Info-ZIP
"""
function unzip_infozip(zippath, dirpath)
    try
        run(`unzip -qq $(zippath) -d $(dirpath)`)
    catch
        # unzip errors if the zip file is empty for some reason
    end
    nothing
end


unzippers = Any[
    unzip_p7zip,
    unzip_bsdtar,
]

if have_python()
    push!(unzippers, unzip_python)
else
    @info "python not found, skipping `unzip_python` tests"
end

if have_infozip()
    push!(unzippers, unzip_infozip)
else
    @info "system Info-ZIP unzip not found, skipping `unzip_infozip` tests"
end
