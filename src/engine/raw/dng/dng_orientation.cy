import .engine.tiff.tiff;

// TIFF Orientation belongs to the root IFD for this bounded Classic TIFF DNG
// path. Missing tag has TIFF's default value 1. Values outside 1..8 and
// duplicate or malformed tags are not accepted as renderable orientation.
pub fn probe(input: *const u8, length: usize, output: *u32, output_len: usize): i32 {
    const size = length as usize;
    if output_len as usize != 1 or not tiff.has_range(size, 0, 8) {
        return 4;
    }
    if tiff.byte(input, 0) != 73 or tiff.byte(input, 1) != 73 or tiff.u16le(input, 2) != 42 {
        return 2;
    }
    const ifd = tiff.u32le(input, 4) as usize;
    if not tiff.has_range(size, ifd, 2) {
        return 1;
    }
    const count = tiff.u16le(input, ifd) as usize;
    if count > (size - ifd - 2) / 12 or not tiff.has_range(size, ifd + 2 + count * 12, 4) {
        return 1;
    }
    var orientation: u32 = 1;
    var found = false;
    var index: usize = 0;
    while index < count {
        const entry = ifd + 2 + index * 12;
        if tiff.u16le(input, entry) == 274 {
            const kind = tiff.u16le(input, entry + 2);
            const elements = tiff.u32le(input, entry + 4);
            const value = tiff.u32le(input, entry + 8);
            if found or kind != 3 or elements != 1 or value > 65535 or value < 1 or value > 8 {
                return 2;
            }
            orientation = value;
            found = true;
        }
        index = index + 1;
    }
    unchecked {
        *output = orientation as u32;
    }
    return 0;
}
