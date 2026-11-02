import .engine.core.core;

pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
pub const bin_count: usize = 258;

pub struct HistogramAsset {
    pub version: u32;
}

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

// Immutable interleaved scene-linear Rec.2020/D65 f32 RGB in [-0.25,8],
// top-left row-major. Output is 258 u32 counts: negative luminance, 256
// bins over [0,1), and Y >= 1. Status 0 success, 1 version, 2 geometry or
// pixel limit, 3 input sample, 4 output shape, 7 cancellation. All input is
// validated in a first pass before zeroing/counting; both passes poll each
// row. Nonzero status invalidates all output counts. No pixel output or halo.
pub fn build(input: []const f32, width: usize, height: usize,
    asset: HistogramAsset, output: []u32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if asset.version != algorithm_version {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 {
        return 2;
    }
    if output.len() != bin_count {
        return 4;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const offset = (row * width + column) * 3;
            var channel: usize = 0;
            while channel < 3 {
                const value = input[offset + channel];
                if not core.finite_sample(value) or value < -0.25
                or value > 8.0 {
                    return 3;
                }
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    var index: usize = 0;
    while index < bin_count {
        output[index] = 0;
        index = index + 1;
    }
    row = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const offset = (row * width + column) * 3;
            const red = input[offset] as f64;
            const green = input[offset + 1] as f64;
            const blue = input[offset + 2] as f64;
            const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
            const bin = bin_for_luminance(y);
            output[bin] = output[bin] + 1;
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}

fn wide_count_fits(current: u64, added: u64, limit: u64): bool {
    return current <= limit and added <= limit - current;
}

fn read_total(input: *u8, index: usize): u64 {
    unchecked {
        return *(((input as! usize) + index * 8) as! *u64);
    }
}

fn write_total(output: *u8, index: usize, value: u64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *u64) = value;
    }
}

// Merge one complete tile into a bounded full-frame analysis result.
// Status: 0 success, 2 count limit, 3 shape. All counts are validated before
// the aggregate is changed. Source counts remain immutable.
fn merge_working_luminance_histogram(tile: *const u32, tile_len: usize, aggregate: *u8, aggregate_len: usize, max_pixels: usize): i32 {
    if tile_len as usize != 258 or aggregate_len as usize != 258 * 8 {
        return 3;
    }
    var total: u64 = 0;
    var index: usize = 0;
    while index < 258 {
        const added = read_count(tile as! *u32, index) as u32;
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
        const added = read_count(tile as! *u32, index) as u64;
        write_total(aggregate, index, read_total(aggregate, index) + added);
        index = index + 1;
    }
    return 0;
}

fn read_sample(input: *const f32, index: usize): f32 {
    unchecked {
        return *(((input as! usize) + index * 4) as! *const f32);
    }
}

fn read_count(output: *u32, index: usize): u32 {
    unchecked {
        return *(((output as! usize) + index * 4) as! *u32);
    }
}

fn write_count(output: *u32, index: usize, value: u32): void {
    unchecked {
        *(((output as! usize) + index * 4) as! *u32) = value;
    }
}

// Status: 0 success, 1 extent, 2 resource limit, 3 shape, 5 samples.
// At most 16,777,216 pixels, so each u32 bin cannot overflow.
fn working_luminance_histogram(input: *const f32, input_len: usize, width: usize, height: usize, max_pixels: usize, output: *u32, output_len: usize): i32 {
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
