using ArgCheck

"Compression method that does no compression"
const Store = UInt16(0)

"Deflate compression method"
const Deflate = UInt16(8)

"Zstd compression method"
const Zstd = UInt16(93)

const _Method2Str = Dict{UInt16,String}(Store => "Store", Deflate => "Deflate", Zstd => "Zstd")

"""
see https://github.com/madler/zipflow/blob/2bef2123ebe519c17b18d2d0c3c71065088de952/zipflow.c#L214
"""
function deflate_level_bits(level::Int)::UInt16
    @argcheck level ∈ (-1:9)
    if level == 9
        0b010 # Maximum
    elseif level == 2
        0b100 # Fast
    elseif level == 1
        0b110 # Super Fast
    else
        0b000 # Normal
    end
end


"External file attributes are compatible with UNIX"
const UNIX = UInt8(3)