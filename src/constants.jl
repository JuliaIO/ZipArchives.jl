"Compression method that does no compression"
const Store = UInt16(0)

"Deflate compression method"
const Deflate = UInt16(8)

"Deflate64 compression method"
const Deflate64 = UInt16(9)

#=
see https://github.com/madler/zipflow/blob/2bef2123ebe519c17b18d2d0c3c71065088de952/zipflow.c#L214
=#
function deflate_level_bits(level::Int)::UInt16
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

const EOCDSig = b"PK\x05\x06"