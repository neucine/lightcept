import .engine.raw.dng.dng_source;

// Scalar 3x3 Bayer bilinear reconstruction in normalized camera RGB.
// For a missing channel, average the samples of that channel in the 3x3
// neighborhood. At image edges, only in-bounds neighbors participate.
// The measured channel is never replaced. Version 1 is intentionally a
// deterministic baseline for later edge-aware algorithms.

pub struct CameraRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn valid_pattern(cfa: [4]u32): bool {
    return (cfa[0] == 0 and cfa[1] == 1 and cfa[2] == 1 and cfa[3] == 2)
    or (cfa[0] == 2 and cfa[1] == 1 and cfa[2] == 1 and cfa[3] == 0)
    or (cfa[0] == 1 and cfa[1] == 0 and cfa[2] == 2 and cfa[3] == 1)
    or (cfa[0] == 1 and cfa[1] == 2 and cfa[2] == 0 and cfa[3] == 1);
}

fn normalized_sample(input: *const c_float, index: usize): f64 {
    unchecked {
        return *(((input as! usize) + index * 4) as! *const c_float) as f64;
    }
}

fn normalized_color(cfa: [4]u32, row: usize, column: usize): u32 {
    return cfa[(row % 2) * 2 + column % 2];
}

fn normalized_interpolate(input: *const c_float, width: usize, height: usize, cfa: [4]u32, row: usize, column: usize, channel: u32): f64 {
    if normalized_color(cfa, row, column) == channel {
        return normalized_sample(input, row * width + column);
    }
    var top = row;
    var bottom = row;
    var left = column;
    var right = column;
    if row > 0 {
        top = row - 1;
    }
    if row + 1 < height {
        bottom = row + 1;
    }
    if column > 0 {
        left = column - 1;
    }
    if column + 1 < width {
        right = column + 1;
    }
    var sum: f64 = 0.0;
    var count: usize = 0;
    var y = top;
    while y <= bottom {
        var x = left;
        while x <= right {
            if normalized_color(cfa, y, x) == channel {
                sum = sum + normalized_sample(input, y * width + x);
                count = count + 1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    return sum / count as f64;
}

pub fn normalized_pixel(input: *const c_float, width: usize, height: usize, cfa: [4]u32, row: usize, column: usize): CameraRgb {
    return {
        red: normalized_interpolate(input, width, height, cfa, row, column, 0),
        green: normalized_interpolate(input, width, height, cfa, row, column, 1),
        blue: normalized_interpolate(input, width, height, cfa, row, column, 2)
    };
}

fn normalized_at(input: *const c_float, width: usize, row: usize, column: usize): f64 {
    return normalized_sample(input, row * width + column);
}

// Malvar-He-Cutler 5x5 gradient-corrected linear filters, coefficients / 8.
// The measured channel is preserved. The outer two pixels use bilinear v1
// because the complete 5x5 support is unavailable there.
fn mhc_green_at_red_or_blue(input: *const c_float, width: usize, row: usize, column: usize): f64 {
    const center = normalized_at(input, width, row, column);
    const near = normalized_at(input, width, row - 1, column) + normalized_at(input, width, row + 1, column) + normalized_at(input, width, row, column - 1) + normalized_at(input, width, row, column + 1);
    const far = normalized_at(input, width, row - 2, column) + normalized_at(input, width, row + 2, column) + normalized_at(input, width, row, column - 2) + normalized_at(input, width, row, column + 2);
    return (4.0 * center + 2.0 * near - far) / 8.0;
}

fn mhc_opposite_at_red_or_blue(input: *const c_float, width: usize, row: usize, column: usize): f64 {
    const center = normalized_at(input, width, row, column);
    const diagonal = normalized_at(input, width, row - 1, column - 1) + normalized_at(input, width, row - 1, column + 1) + normalized_at(input, width, row + 1, column - 1) + normalized_at(input, width, row + 1, column + 1);
    const far = normalized_at(input, width, row - 2, column) + normalized_at(input, width, row + 2, column) + normalized_at(input, width, row, column - 2) + normalized_at(input, width, row, column + 2);
    return (6.0 * center + 2.0 * diagonal - 1.5 * far) / 8.0;
}

fn mhc_at_green_horizontal(input: *const c_float, width: usize, row: usize, column: usize): f64 {
    const center = normalized_at(input, width, row, column);
    const horizontal = normalized_at(input, width, row, column - 1) + normalized_at(input, width, row, column + 1);
    const diagonal = normalized_at(input, width, row - 1, column - 1) + normalized_at(input, width, row - 1, column + 1) + normalized_at(input, width, row + 1, column - 1) + normalized_at(input, width, row + 1, column + 1);
    const horizontal_far = normalized_at(input, width, row, column - 2) + normalized_at(input, width, row, column + 2);
    const vertical_far = normalized_at(input, width, row - 2, column) + normalized_at(input, width, row + 2, column);
    return (5.0 * center + 4.0 * horizontal - diagonal - horizontal_far + 0.5 * vertical_far) / 8.0;
}

fn mhc_at_green_vertical(input: *const c_float, width: usize, row: usize, column: usize): f64 {
    const center = normalized_at(input, width, row, column);
    const vertical = normalized_at(input, width, row - 1, column) + normalized_at(input, width, row + 1, column);
    const diagonal = normalized_at(input, width, row - 1, column - 1) + normalized_at(input, width, row - 1, column + 1) + normalized_at(input, width, row + 1, column - 1) + normalized_at(input, width, row + 1, column + 1);
    const horizontal_far = normalized_at(input, width, row, column - 2) + normalized_at(input, width, row, column + 2);
    const vertical_far = normalized_at(input, width, row - 2, column) + normalized_at(input, width, row + 2, column);
    return (5.0 * center + 4.0 * vertical - diagonal - vertical_far + 0.5 * horizontal_far) / 8.0;
}

pub fn normalized_mhc_pixel(input: *const c_float, width: usize, height: usize, cfa: [4]u32, row: usize, column: usize): CameraRgb {
    if width < 5 or height < 5 or row < 2 or column < 2 or row + 2 >= height or column + 2 >= width {
        return normalized_pixel(input, width, height, cfa, row, column);
    }
    const measured = normalized_color(cfa, row, column);
    const center = normalized_at(input, width, row, column);
    if measured == 0 {
        return {
            red: center,
            green: mhc_green_at_red_or_blue(input, width, row, column),
            blue: mhc_opposite_at_red_or_blue(input, width, row, column)
        };
    }
    if measured == 2 {
        return {
            red: mhc_opposite_at_red_or_blue(input, width, row, column),
            green: mhc_green_at_red_or_blue(input, width, row, column),
            blue: center
        };
    }
    if normalized_color(cfa, row, column - 1) == 0 {
        return {
            red: mhc_at_green_horizontal(input, width, row, column),
            green: center,
            blue: mhc_at_green_vertical(input, width, row, column)
        };
    }
    return {
        red: mhc_at_green_vertical(input, width, row, column),
        green: center,
        blue: mhc_at_green_horizontal(input, width, row, column)
    };
}

fn magnitude(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}

// Hamilton-Adams: estimate green along the lower-variation axis, then
// bilinearly interpolate green-minus-color differences at R/B sample sites.
fn ha_green(input: *const c_float, width: usize, cfa: [4]u32, row: usize, column: usize): f64 {
    if normalized_color(cfa, row, column) == 1 {
        return normalized_at(input, width, row, column);
    }
    const center = normalized_at(input, width, row, column);
    const left = normalized_at(input, width, row, column - 1);
    const right = normalized_at(input, width, row, column + 1);
    const up = normalized_at(input, width, row - 1, column);
    const down = normalized_at(input, width, row + 1, column);
    const left_far = normalized_at(input, width, row, column - 2);
    const right_far = normalized_at(input, width, row, column + 2);
    const up_far = normalized_at(input, width, row - 2, column);
    const down_far = normalized_at(input, width, row + 2, column);
    const horizontal_variation = magnitude(left - right) + magnitude(2.0 * center - left_far - right_far);
    const vertical_variation = magnitude(up - down) + magnitude(2.0 * center - up_far - down_far);
    const horizontal = 0.5 * (left + right) + 0.25 * (2.0 * center - left_far - right_far);
    const vertical = 0.5 * (up + down) + 0.25 * (2.0 * center - up_far - down_far);
    if horizontal_variation < vertical_variation {
        return horizontal;
    }
    if vertical_variation < horizontal_variation {
        return vertical;
    }
    return 0.5 * (horizontal + vertical);
}

fn ha_color_difference(input: *const c_float, width: usize, cfa: [4]u32, row: usize, column: usize): f64 {
    return ha_green(input, width, cfa, row, column) - normalized_at(input, width, row, column);
}

fn ha_missing_color(input: *const c_float, width: usize, cfa: [4]u32, row: usize, column: usize, target: u32, green: f64): f64 {
    var difference: f64 = 0.0;
    if normalized_color(cfa, row, column) == 1 {
        if normalized_color(cfa, row, column - 1) == target {
            difference = 0.5 * (ha_color_difference(input, width, cfa, row, column - 1) + ha_color_difference(input, width, cfa, row, column + 1));
        } else {
            difference = 0.5 * (ha_color_difference(input, width, cfa, row - 1, column) + ha_color_difference(input, width, cfa, row + 1, column));
        }
    } else {
        difference = 0.25 * (ha_color_difference(input, width, cfa, row - 1, column - 1) + ha_color_difference(input, width, cfa, row - 1, column + 1) + ha_color_difference(input, width, cfa, row + 1, column - 1) + ha_color_difference(input, width, cfa, row + 1, column + 1));
    }
    return green - difference;
}

pub fn normalized_ha_pixel(input: *const c_float, width: usize, height: usize, cfa: [4]u32, row: usize, column: usize): CameraRgb {
    if width < 7 or height < 7 or row < 3 or column < 3 or row + 3 >= height or column + 3 >= width {
        return normalized_pixel(input, width, height, cfa, row, column);
    }
    const measured = normalized_color(cfa, row, column);
    const center = normalized_at(input, width, row, column);
    const green = ha_green(input, width, cfa, row, column);
    if measured == 0 {
        return {
            red: center,
            green: green,
            blue: ha_missing_color(input, width, cfa, row, column, 2, green)
        };
    }
    if measured == 2 {
        return {
            red: ha_missing_color(input, width, cfa, row, column, 0, green),
            green: green,
            blue: center
        };
    }
    return {
        red: ha_missing_color(input, width, cfa, row, column, 0, green),
        green: center,
        blue: ha_missing_color(input, width, cfa, row, column, 2, green)
    };
}

fn interpolate(input: *const c_uchar, info: dng_source.DngInfo, row: usize, column: usize, channel: u32): f64 {
    if dng_source.mosaic_color(info, row, column) == channel {
        return dng_source.mosaic_sample(input, info, row, column);
    }
    var top = row;
    var bottom = row;
    var left = column;
    var right = column;
    if row > 0 {
        top = row - 1;
    }
    if row + 1 < info.height {
        bottom = row + 1;
    }
    if column > 0 {
        left = column - 1;
    }
    if column + 1 < info.width {
        right = column + 1;
    }
    var sum: f64 = 0.0;
    var count: usize = 0;
    var y = top;
    while y <= bottom {
        var x = left;
        while x <= right {
            if dng_source.mosaic_color(info, y, x) == channel {
                sum = sum + dng_source.mosaic_sample(input, info, y, x);
                count = count + 1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    return sum / (count as f64);
}

pub fn pixel(input: *const c_uchar, info: dng_source.DngInfo, row: usize, column: usize): CameraRgb {
    return {
        red: interpolate(input, info, row, column, 0),
        green: interpolate(input, info, row, column, 1),
        blue: interpolate(input, info, row, column, 2),
    };
}

fn write_sample(output: *c_double, index: usize, value: f64): void {
    unchecked {
        const address = (output as! usize) + index * 8;
        *(address as! *c_double) = value as c_double;
    }
}

// Stage-level diagnostic: normalized Bayer samples to scene-linear camera RGB.
// The ABI exposes the reconstruction before white balance, color conversion,
// exposure, resampling, or display encoding for matched-algorithm verification.
export c("lc_cyna_img_v1_demosaic_normalized_bayer") fn demosaic_normalized_bayer(input: *const c_float, input_len: c_size_t, width: c_size_t, height: c_size_t, cfa_input: *const c_uint, cfa_len: c_size_t, output: *c_double, output_len: c_size_t, method: c_uint): c_int {
    const w = width as usize;
    const h = height as usize;
    if w < 2 or h < 2 or w > 33554432 / h or input_len as usize != w * h or output_len as usize != w * h * 3 or cfa_len as usize != 4 or (method != 1 and method != 2 and method != 3) {
        return 4;
    }
    var cfa: [4]u32 = [0, 0, 0, 0];
    var phase: usize = 0;
    while phase < 4 {
        unchecked {
            cfa[phase] = *(((cfa_input as! usize) + phase * 4) as! *const c_uint) as u32;
        }
        phase = phase + 1;
    }
    if not valid_pattern(cfa) {
        return 2;
    }
    var index: usize = 0;
    while index < w * h {
        var bits: u32 = 0;
        unchecked {
            bits = *(((input as! usize) + index * 4) as! *const c_uint) as u32;
        }
        if (bits & 0x7f800000) == 0x7f800000 {
            return 1;
        }
        const sample = normalized_sample(input, index);
        if sample != sample or sample < -65536.0 or sample > 65536.0 {
            return 1;
        }
        index = index + 1;
    }
    index = 0;
    while index < w * h {
        const row = index / w;
        const column = index % w;
        var camera: CameraRgb = {
            red: 0.0,
            green: 0.0,
            blue: 0.0
        };
        if method == 2 {
            camera = normalized_mhc_pixel(input, w, h, cfa, row, column);
        } else if method == 3 {
            camera = normalized_ha_pixel(input, w, h, cfa, row, column);
        } else {
            camera = normalized_pixel(input, w, h, cfa, row, column);
        }
        write_sample(output, index * 3, camera.red);
        write_sample(output, index * 3 + 1, camera.green);
        write_sample(output, index * 3 + 2, camera.blue);
        index = index + 1;
    }
    return 0;
}

// Band-limited companion for the diagnostic spatial highlight path. The
// caller validates the full normalized input before the first band. Pixel
// kernels still see the full image, so band boundaries do not alter results.
fn demosaic_normalized_bayer_rows_bounded(input: *const c_float, input_len: c_size_t, width: c_size_t, height: c_size_t, cfa_input: *const c_uint, cfa_len: c_size_t, row_start: c_size_t, row_count: c_size_t, output: *c_double, output_len: c_size_t, method: c_uint, max_pixels: usize): c_int {
    const w = width as usize;
    const h = height as usize;
    const start = row_start as usize;
    const rows = row_count as usize;
    if w < 2 or h < 2 or w > max_pixels / h or input_len as usize != w * h or cfa_len as usize != 4 or (method != 1 and method != 2 and method != 3) or start >= h or rows == 0 or rows > h - start or output_len as usize != rows * w * 3 {
        return 4;
    }
    var cfa: [4]u32 = [0, 0, 0, 0];
    var phase: usize = 0;
    while phase < 4 {
        unchecked {
            cfa[phase] = *(((cfa_input as! usize) + phase * 4) as! *const c_uint) as u32;
        }
        phase = phase + 1;
    }
    if not valid_pattern(cfa) {
        return 2;
    }
    var index: usize = 0;
    while index < rows * w {
        const row = start + index / w;
        const column = index % w;
        var camera: CameraRgb = {
            red: 0.0,
            green: 0.0,
            blue: 0.0
        };
        if method == 2 {
            camera = normalized_mhc_pixel(input, w, h, cfa, row, column);
        } else if method == 3 {
            camera = normalized_ha_pixel(input, w, h, cfa, row, column);
        } else {
            camera = normalized_pixel(input, w, h, cfa, row, column);
        }
        write_sample(output, index * 3, camera.red);
        write_sample(output, index * 3 + 1, camera.green);
        write_sample(output, index * 3 + 2, camera.blue);
        index = index + 1;
    }
    return 0;
}

export c("lc_cyna_img_v2_demosaic_normalized_bayer_rows") fn demosaic_normalized_bayer_rows(input: *const c_float, input_len: c_size_t, width: c_size_t, height: c_size_t, cfa_input: *const c_uint, cfa_len: c_size_t, row_start: c_size_t, row_count: c_size_t, output: *c_double, output_len: c_size_t, method: c_uint): c_int {
    return demosaic_normalized_bayer_rows_bounded(input, input_len, width, height, cfa_input, cfa_len, row_start, row_count, output, output_len, method, 33554432);
}

// Z8 active area exceeds the original 32 Mi-pixel diagnostic limit. The
// caller owns the bounded raster; only one band is returned per invocation.
pub export c("lc_cyna_img_v3_demosaic_normalized_bayer_rows") fn demosaic_normalized_bayer_rows_camera(input: *const c_float, input_len: c_size_t, width: c_size_t, height: c_size_t, cfa_input: *const c_uint, cfa_len: c_size_t, row_start: c_size_t, row_count: c_size_t, output: *c_double, output_len: c_size_t, method: c_uint): c_int {
    return demosaic_normalized_bayer_rows_bounded(input, input_len, width, height, cfa_input, cfa_len, row_start, row_count, output, output_len, method, 50000000);
}

export c("lc_cyna_img_v1_decode_bayer_dng") fn decode(input: *const c_uchar, length: c_size_t, output: *c_double, output_len: c_size_t, max_pixels: c_size_t): c_int {
    const info = dng_source.inspect(input, length as usize, max_pixels as usize);
    if info.status != 0 {
        return info.status;
    }
    if info.photometric != 32803 {
        return 2;
    }
    if output_len as usize != info.width * info.height * 3 {
        return 4;
    }
    var index: usize = 0;
    while index < info.width * info.height {
        const camera = pixel(input, info, index / info.width, index % info.width);
        write_sample(output, index * 3, camera.red);
        write_sample(output, index * 3 + 1, camera.green);
        write_sample(output, index * 3 + 2, camera.blue);
        index = index + 1;
    }
    return 0;
}
