# ZipArchives.jl Fixture

This directory contains a number of zip archives 
that should be able to be successfully read.

### How to add new files
Download the fixture with 
```julia
using Pkg.Artifacts
fixture_dir = "fixture"
cp(joinpath(artifact"fixture","fixture"), fixture_dir)
```

Add the file to the "fixture" directory, and a description to this file.

Then run
```julia
# This is the url that the artifact will be available from:
url_to_upload_to = "https://github.com/medyan-dev/ZipArchives.jl/releases/download/v2.1.6/fixture.tar.gz"
# This is the path to the Artifacts.toml we will manipulate
artifact_toml = "Artifacts.toml"
fixture_hash = create_artifact() do artifact_dir
    cp(fixture_dir, joinpath(artifact_dir,"fixture"))
end
tar_hash = archive_artifact(fixture_hash, "fixture.tar.gz")
bind_artifact!(artifact_toml, "fixture", fixture_hash; force=true,
    download_info = [(url_to_upload_to, tar_hash)]
)
```

Finally, upload the new "fixture.tar.gz" to `url_to_upload_to`

## `dotnet-deflate64.zip`
This file is downloaded from https://github.com/dotnet/runtime-assets/blob/95277f38e68b66f1b48600d90d456c32c9ae0fa2/src/System.IO.Compression.TestData/ZipTestData/compat/deflate64.zip

## `leftpad-core_2.13-0.1.11.jar`
Example jar file from https://mvnrepository.com/artifact/io.github.asakaev/leftpad-core_2.13/0.1.11

## `ubuntu22-7zip.zip`
Created with 7zip version 22.01 (x64)

## `ubuntu22-files.zip`
Created with default ubuntu files program

## `ubuntu22-infozip.zip`
Small zip file created with ubuntu22 Info-ZIP Zip 3.0

## `ubuntu22-old7zip.zip`
Created with 7zip version 16.02 p7zip 16.02

## `win11-7zip.zip`
Small zip file created with windows 11 7Zip 22.01

## `win11-deflate64.zip`
Large zip file created with windows 11 file explorer.
Designed to test the deflate64 decompressor.

## `win11-excel.ods`
Small OpenDocument Spreadsheet file created on windows 11 in microsoft Excel version 2305.

## `win11-excel.xlsx`
Small excel file created on windows 11 in microsoft Excel version 2305.

## `win11-explorer.zip`
Small zip file created with windows 11 file explorer

## `win11-infozip.zip`
Small zip file created with windows 11 Info-ZIP Zip 3.0

## `win11-julia-p7zip.zip`
Small zip file created with windows 11 p7zip_jll 17.4.0+0

## `win11-libreoffice.ods`
Small OpenDocument Spreadsheet file created on windows 11 in LibreOffice Calc 7.5

## `win11-powerpoint.odp`
Small odp file created on windows 11 in microsoft PowerPoint version 2305

## `win11-powerpoint.pptx`
Small pptx file created on windows 11 in microsoft PowerPoint version 2305

## `ZipArchives.jl-main.zip`
Zip file downloaded from a github on 20 JUN 2023

## `zipfile-deflate64.zip`
Test file from https://github.com/brianhelba/zipfile-deflate64/blob/beec33184da6da4697a1994c0ac4c64cef8cff50/tests/data/deflate64.zip