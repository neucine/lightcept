// Nikon NEF sensor geometry and level normalization, algorithm version 1.
// Input: uncropped unsigned sensor codes in stored raster order. Crop values
// are absolute stored-pixel coordinates. Black and white are sensor code units.
// Output: cropped camera-mosaic values (raw-black)/(white-black), row-major;
// negative and above-one values remain available for later stages.

// Convert the stored 2x2 CFA byte pattern to the cropped mosaic's local
// top-left origin. Each byte is 0 red, 1 green, or 2 blue in row-major order.
pub fn cropped_cfa(stored: u32, left: u32, top: u32): u32 {
    var shifted: u32 = 0;
    var row: u32 = 0;
    while row < 2 {
        var column: u32 = 0;
        while column < 2 {
            const source_index = ((top + row) % 2) * 2 + (left + column) % 2;
            const channel = (stored >> (source_index * 8)) % 256;
            shifted = shifted + (channel << ((row * 2 + column) * 8));
            column = column + 1;
        }
        row = row + 1;
    }
    return shifted;
}

fn sample(input: *const c_ushort, index: usize): u32 {
    unchecked {
        return *(((input as! usize) + index * 2) as! *const c_ushort) as u32;
    }
}

fn write(output: *c_float, index: usize, value: f32): void {
    unchecked {
        *(((output as! usize) + index * 4) as! *c_float) = value as c_float;
    }
}

pub export c("lc_cyna_img_v1_normalize_nef_sensor") fn normalize(
    input: *const c_ushort, input_len: c_size_t,
    stored_width: c_size_t, stored_height: c_size_t,
    crop_left: c_size_t, crop_top: c_size_t,
    crop_width: c_size_t, crop_height: c_size_t,
    black00: c_uint, black01: c_uint, black10: c_uint, black11: c_uint,
    white: c_uint,
    output: *c_float, output_len: c_size_t,
    cancelled: c fn (*const c_uchar): c_int, cancel_context: *const c_uchar
): c_int {
    if (input as! usize) == 0 or (output as! usize) == 0 {
        return 4;
    }
    const w = stored_width as usize;
    const h = stored_height as usize;
    const left = crop_left as usize;
    const top = crop_top as usize;
    const cw = crop_width as usize;
    const ch = crop_height as usize;
    if w == 0 or h == 0 or w > 10000 or h > 10000 or w > 100000000 / h {
        return 3;
    }
    if input_len as usize != w * h or cw == 0 or ch == 0 or left > w or top > h or cw > w - left or ch > h - top {
        return 4;
    }
    if cw > 100000000 / ch or output_len as usize != cw * ch {
        return 4;
    }
    if white > 16383 or black00 >= white or black01 >= white or black10 >= white or black11 >= white {
        return 1;
    }
    const black: [4]u32 = [black00 as u32, black01 as u32, black10 as u32, black11 as u32];
    var row: usize = 0;
    while row < ch {
        if cancelled(cancel_context) != 0 {
            return 7;
        }
        var column: usize = 0;
        while column < cw {
            const y = top + row;
            const x = left + column;
            const index = (y % 2) * 2 + x % 2;
            const code = sample(input, y * w + x);
            if code > 16383 {
                return 1;
            }
            const level = black[index];
            const value = (code as f32 - level as f32) / ((white as u32) - level) as f32;
            write(output, row * cw + column, value);
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
