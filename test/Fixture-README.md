# ZipArchives.jl Fixture

This directory contains a number of zip archives 
that should be able to be successfully read.

### How to add new files
Download the fixture with 
```julia
using Pkg.Artifacts
fixture_dir = joinpath(@__DIR__, "fixture")
cp(joinpath(artifact"fixture","fixture"), fixture_dir)
```

Add the file to the "fixture" directory, and a description to this file.

Then run
```julia
# This is the path to the Artifacts.toml we will manipulate
artifact_toml = joinpath(@__DIR__, "Artifacts.toml")
fixture_hash = create_artifact() do artifact_dir
    cp(fixture_dir, joinpath(artifact_dir,"fixture"))
end
bind_artifact!(artifact_toml, "fixture", fixture_hash; force=true)
tar_hash = archive_artifact(fixture_hash, "fixture.tar.gz")
```

Finally, upload the new "fixture.tar.gz" to github and update the 
download section of the "Artifacts.toml"

## `win11-excel.xlsx`
Small excel file created on windows 11 in microsoft Excel version 2305.

## `win11-excel.ods`
Small OpenDocument Spreadsheet file created on windows 11 in microsoft Excel version 2305.

## `win11-libreoffice.ods`
Small OpenDocument Spreadsheet file created on windows 11 in LibreOffice Calc 7.5

## `win11-explorer.zip`
Small zip file created with windows 11 file explorer

## `win11-infozip.zip`
Small zip file created with windows 11 Info-ZIP Zip 3.0

## `win11-7zip.zip`
Small zip file created with windows 11 7Zip 22.01

## `win11-julia-p7zip.zip`
Small zip file created with windows 11 p7zip_jll 17.4.0+0

## `win11-powerpoint.odp`
Small odp file created on windows 11 in microsoft PowerPoint version 2305

## `win11-powerpoint.pptx`
Small pptx file created on windows 11 in microsoft PowerPoint version 2305

## `ZipArchives.jl-main.zip`
Zip file downloaded from a github on 20 JUN 2023

## `leftpad-core_2.13-0.1.11.jar`
Example jar file from https://mvnrepository.com/artifact/io.github.asakaev/leftpad-core_2.13/0.1.11

## `ubuntu22-files.zip`
Created with default ubuntu files program

## `ubuntu22-7zip.zip
Created with 7zip version 22.01 (x64)

## `ubuntu22-old7zip.zip
Created with 7zip version 16.02 p7zip 16.02

## `ubuntu22-infozip.zip`
Small zip file created with ubuntu22 Info-ZIP Zip 3.0