// Bounded Classic TIFF RGB16 encoder v1 for already developed encoded sRGB.
// Input is interleaved RGB u16 in visual top-left row-major order; output is
// little-endian uncompressed TIFF bytes. The caller owns both buffers and the
// exact output ICC profile. No source EXIF, GPS, or maker notes are copied.
// At most 50 million pixels and 65536 ICC bytes. A nonzero status invalidates
// the output; cancellation is checked before writing and at each row.
// Status: 0 success, 2 invalid ICC, 3 resource limit, 4 shape, 7 cancelled.

pub struct Layout {
    pub pixel_offset: usize;
    pub total_bytes: usize;
    pub status: c_int;
}

pub fn layout(width: usize, height: usize, icc_length: usize): Layout {
    if width == 0 or height == 0 or width > 10000 or height > 10000 {
        return {
            pixel_offset: 0,
            total_bytes: 0,
            status: 4
        };
    }
    if width > 50000000 / height {
        return {
            pixel_offset: 0,
            total_bytes: 0,
            status: 3
        };
    }
    if icc_length < 128 or icc_length > 65536 {
        return {
            pixel_offset: 0,
            total_bytes: 0,
            status: 2
        };
    }
    var pixel_offset = 164 + icc_length;
    if pixel_offset % 2 != 0 {
        pixel_offset = pixel_offset + 1;
    }
    return {
        pixel_offset: pixel_offset,
        total_bytes: pixel_offset + width * height * 6,
        status: 0
    };
}

fn put16(output: []u8, offset: usize, value: u16): void {
    output[offset] = (value % 256) as u8;
    output[offset + 1] = (value / 256) as u8;
}

fn put32(output: []u8, offset: usize, value: u32): void {
    put16(output, offset, (value % 65536) as u16);
    put16(output, offset + 2, (value / 65536) as u16);
}

fn tag(output: []u8, index: usize, id: u16, kind: u16, count: u32, value: u32): void {
    const offset = 10 + index * 12;
    put16(output, offset, id);
    put16(output, offset + 2, kind);
    put32(output, offset + 4, count);
    put32(output, offset + 8, value);
}

// Header length is layout.pixel_offset; each subsequent row is width * 6 bytes.
// A caller can write these buffers in order without allocating total_bytes.
pub fn encode_header(width: usize, height: usize, icc: []const u8, output: []u8,
    cancelled: c fn (*const c_uchar): c_int, context: *const c_uchar
): c_int {
    const plan = layout(width, height, icc.len());
    if plan.status != 0 {
        return plan.status;
    }
    if output.len() != plan.pixel_offset {
        return 4;
    }
    if icc[36] != 97 or icc[37] != 99 or icc[38] != 115 or icc[39] != 112 {
        return 2;
    }
    if cancelled(context) != 0 {
        return 7;
    }
    output[0] = 73;
    output[1] = 73;
    put16(output, 2, 42);
    put32(output, 4, 8);
    put16(output, 8, 12);
    tag(output, 0, 256, 4, 1, width as u32);
    tag(output, 1, 257, 4, 1, height as u32);
    tag(output, 2, 258, 3, 3, 158);
    tag(output, 3, 259, 3, 1, 1);
    tag(output, 4, 262, 3, 1, 2);
    tag(output, 5, 273, 4, 1, plan.pixel_offset as u32);
    tag(output, 6, 274, 3, 1, 1);
    tag(output, 7, 277, 3, 1, 3);
    tag(output, 8, 278, 4, 1, height as u32);
    tag(output, 9, 279, 4, 1, (width * height * 6) as u32);
    tag(output, 10, 284, 3, 1, 1);
    tag(output, 11, 34675, 1, icc.len() as u32, 164);
    put32(output, 154, 0);
    put16(output, 158, 16);
    put16(output, 160, 16);
    put16(output, 162, 16);
    var index: usize = 0;
    while index < icc.len() {
        output[164 + index] = icc[index];
        index = index + 1;
    }
    if (164 + icc.len()) < plan.pixel_offset {
        output[plan.pixel_offset - 1] = 0;
    }
    return 0;
}

// Input is one interleaved RGB16 row. Output is exactly width * 6 bytes.
pub fn encode_row(rgb: []const u16, width: usize, output: []u8,
    cancelled: c fn (*const c_uchar): c_int, context: *const c_uchar
): c_int {
    if width == 0 or width > 10000 or rgb.len() != width * 3 or output.len() != width * 6 {
        return 4;
    }
    if cancelled(context) != 0 {
        return 7;
    }
    var channel: usize = 0;
    while channel < width * 3 {
        put16(output, channel * 2, rgb[channel]);
        channel = channel + 1;
    }
    return 0;
}

pub fn encode(rgb: []const u16, width: usize, height: usize,
    icc: []const u8, output: []u8,
    cancelled: c fn (*const c_uchar): c_int, context: *const c_uchar
): c_int {
    const plan = layout(width, height, icc.len());
    if plan.status != 0 {
        return plan.status;
    }
    if rgb.len() != width * height * 3 or output.len() != plan.total_bytes {
        return 4;
    }
    const header_status = encode_header(width, height, icc, output[0..plan.pixel_offset],
        cancelled, context
    );
    if header_status != 0 {
        return header_status;
    }
    var row: usize = 0;
    while row < height {
        const status = encode_row(rgb[row * width * 3..(row + 1) * width * 3], width,
            output[plan.pixel_offset + row * width * 6..plan.pixel_offset + (row + 1) * width * 6],
            cancelled, context
        );
        if status != 0 {
            return status;
        }
        row = row + 1;
    }
    return 0;
}
