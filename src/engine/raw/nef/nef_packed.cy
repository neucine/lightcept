import .engine.tiff.tiff;

// Nikon packed 14-bit NEF sensor-code decoder, algorithm version 1.
// Input is one bounded packed strip. Samples are unsigned 14-bit values in
// row-major order, least-significant bit first. Each row is padded to a
// 16-byte boundary, matching Nikon's packed NEF layout. Output is uncropped
// sensor codes; no black level, crop, colour, or orientation is applied here.
fn packed_sample(input: *const u8, index: usize): u16 {
    const bit = index * 14;
    const at = bit / 8;
    const word = (tiff.byte(input, at) as u32) +
    ((tiff.byte(input, at + 1) as u32) << 8) +
    ((tiff.byte(input, at + 2) as u32) << 16);
    return ((word >> (bit % 8)) % 16384) as u16;
}

fn put(output: *u16, index: usize, value: u16): void {
    unchecked {
        const address = (output as! usize) + index * 2;
        *(address as! *u16) = value;
    }
}

pub fn decode(
    input: *const u8, length: usize,
    width: usize, height: usize,
    output: *u16, output_len: usize,
    cancelled: fn (usize): bool, context: usize
): i32 {
    const w = width;
    const h = height;
    if w == 0 or h == 0 or w > 10000 or h > 10000 or w > 100000000 / h {
        return 3;
    }
    if output_len != w * h {
        return 4;
    }
    if (input as! usize) == 0 or (output as! usize) == 0 {
        return 4;
    }
    const unpadded_row_bytes = (w * 14 + 7) / 8;
    const row_bytes = ((unpadded_row_bytes + 15) / 16) * 16;
    if row_bytes > length / h or row_bytes * h != length {
        return 1;
    }
    var row: usize = 0;
    while row < h {
        if cancelled(context) {
            return 7;
        }
        const row_input = (input as! usize) + row * row_bytes;
        var column: usize = 0;
        while column < w {
            put(output, row * w + column,
                packed_sample(row_input as! *const u8, column)
            );
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
