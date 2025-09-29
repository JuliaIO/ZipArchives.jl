# ZipArchives.jl benchmarks

This directory contains benchmarks for ZipArchives. To run all the
benchmarks, launch `julia --project=benchmark` and enter:

``` julia
using PkgBenchmark
import ZipArchives

benchmarkpkg(ZipArchives)
```