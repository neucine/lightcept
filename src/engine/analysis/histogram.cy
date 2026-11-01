import .engine.core.core;

// Scene-linear Rec.2020/D65 luminance histogram v1. Output row layout:
// [negative, bins 0..255 for Y in [0,1), Y >= 1]. Exact bin boundaries
// are k/256; no output clipping or display transfer is involved.
pub fn bin_for_luminance(y: f64): usize {
    if y < 0.0 {
        return 0;
    }
    if y >= 1.0 {
        return 257;
    }
    return 1 + (y * 256.0) as usize;
}

pub fn count_fits(current: u64, added: u32, limit: u64): bool {
    return current <= limit and (added as u64) <= limit - current;
}

fn wide_count_fits(current: u64, added: u64, limit: u64): bool {
    return current <= limit and added <= limit - current;
}

fn read_total(input: *c_uchar, index: usize): u64 {
    unchecked {
        return *(((input as! usize) + index * 8) as! *u64);
    }
}

fn write_total(output: *c_uchar, index: usize, value: u64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *u64) = value;
    }
}

// Merge one complete tile into a bounded full-frame analysis result.
// Status: 0 success, 2 count limit, 3 shape. All counts are validated before
// the aggregate is changed. Source counts remain immutable.
export c("lc_cyna_img_v1_merge_working_luminance_histogram") fn merge_working_luminance_histogram(tile: *const c_uint, tile_len: c_size_t, aggregate: *c_uchar, aggregate_len: c_size_t, max_pixels: c_size_t): c_int {
    if tile_len as usize != 258 or aggregate_len as usize != 258 * 8 {
        return 3;
    }
    var total: u64 = 0;
    var index: usize = 0;
    while index < 258 {
        const added = read_count(tile as! *c_uint, index) as u32;
        const current = read_total(aggregate, index);
        if not count_fits(current, added, max_pixels as u64) {
            return 2;
        }
        const combined = current + added as u64;
        if not wide_count_fits(total, combined, max_pixels as u64) {
            return 2;
        }
        total = total + combined;
        index = index + 1;
    }
    index = 0;
    while index < 258 {
        const added = read_count(tile as! *c_uint, index) as u64;
        write_total(aggregate, index, read_total(aggregate, index) + added);
        index = index + 1;
    }
    return 0;
}

fn read_sample(input: *const c_float, index: usize): c_float {
    unchecked {
        return *(((input as! usize) + index * 4) as! *const c_float);
    }
}

fn read_count(output: *c_uint, index: usize): c_uint {
    unchecked {
        return *(((output as! usize) + index * 4) as! *c_uint);
    }
}

fn write_count(output: *c_uint, index: usize, value: c_uint): void {
    unchecked {
        *(((output as! usize) + index * 4) as! *c_uint) = value;
    }
}

// Status: 0 success, 1 extent, 2 resource limit, 3 shape, 5 samples.
// At most 16,777,216 pixels, so each c_uint bin cannot overflow.
export c("lc_cyna_img_v1_working_luminance_histogram") fn working_luminance_histogram(input: *const c_float, input_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, output: *c_uint, output_len: c_size_t): c_int {
    if output_len as usize != 258 {
        return 3;
    }
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, input_len as usize);
    if valid != 0 {
        return valid;
    }
    var index: usize = 0;
    while index < 258 {
        write_count(output, index, 0);
        index = index + 1;
    }
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const y = 0.2627 * (red as f64) + 0.6780 * (green as f64) + 0.0593 * (blue as f64);
        const bin = bin_for_luminance(y);
        write_count(output, bin, read_count(output, bin) + 1);
        pixel = pixel + 1;
    }
    return 0;
}
