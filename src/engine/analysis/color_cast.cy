import .engine.core.core;

// Neutral-reference color cast diagnostic v1. Scene-linear Rec.2020/D65 RGB.
// A caller-supplied neutral rectangle is required; this is evidence, not an
// automatic white-balance decision. Matrix hash identifies upstream color work.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct NeutralRegion {
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
}

pub struct CastReport {
    // 0 success; 1 shape/limit; 2 reference or matrix identity;
    // 3 nonfinite/out-of-domain sample; 4 insufficient signal; 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub matrix_hash: u64;
    pub pixels: usize;
    pub mean_red: f64;
    pub mean_green: f64;
    pub mean_blue: f64;
    // Channel ratios relative to the region's Rec.2020 luminance.
    // A neutral reference has each ratio near one.
    pub red_ratio: f64;
    pub green_ratio: f64;
    pub blue_ratio: f64;
}

fn failure(status: u32): CastReport {
    return {
        status: status,
        version: algorithm_version,
        matrix_hash: 0,
        pixels: 0,
        mean_red: 0.0,
        mean_green: 0.0,
        mean_blue: 0.0,
        red_ratio: 0.0,
        green_ratio: 0.0,
        blue_ratio: 0.0
    };
}

// Input is immutable row-major interleaved f32 RGB, [-0.25,8] scene-linear.
// The rectangle is half-open in pixel-center coordinates. Poll each row.
// Any failure discards all measurements; output pixels are never modified.
pub fn measure(input: []const f32, width: usize, height: usize,
    region: NeutralRegion, matrix_hash: u64,
    cancelled: fn (usize): bool, context: usize
): CastReport {
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(1);
    }
    if input.len() != width * height * 3 {
        return failure(1);
    }
    if matrix_hash == 0 or region.width == 0 or region.height == 0
    or region.left >= width or region.top >= height
    or region.width > width - region.left
    or region.height > height - region.top {
        return failure(2);
    }
    var sums: [3]f64 = [0.0, 0.0, 0.0];
    var row: usize = 0;
    while row < region.height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < region.width {
            const offset = ((region.top + row) * width + region.left + column) * 3;
            var channel: usize = 0;
            while channel < 3 {
                const value = input[offset + channel];
                if not core.finite_sample(value) or value < -0.25 or value > 8.0 {
                    return failure(3);
                }
                sums[channel] = sums[channel] + (value as f64);
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    const pixels = region.width * region.height;
    const count = pixels as f64;
    const red = sums[0] / count;
    const green = sums[1] / count;
    const blue = sums[2] / count;
    const luminance = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    if luminance < 0.001 {
        return failure(4);
    }
    return {
        status: 0,
        version: algorithm_version,
        matrix_hash: matrix_hash,
        pixels: pixels,
        mean_red: red,
        mean_green: green,
        mean_blue: blue,
        red_ratio: red / luminance,
        green_ratio: green / luminance,
        blue_ratio: blue / luminance
    };
}
