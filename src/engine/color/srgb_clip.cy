import .engine.core.core;

// Hard sRGB destination gamut clipping v1 in D65 linear-light RGB.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub fn channel(value: f64): f64 {
    if value <= 0.0 {
        return 0.0;
    }
    if value >= 1.0 {
        return 1.0;
    }
    return value;
}

// Immutable row-major interleaved f32 linear-sRGB input in [-16,16] and
// disjoint same-sized f32 output in [0,1]. Status 0 success, 1 shape/limit,
// 2 invalid input, 7 cancelled. Validate all input before writing; a failed
// output is invalid, including cancellation. Poll every row in both passes.
// No spatial halo or transfer function.
pub fn apply(input: []const f32, width: usize, height: usize,
    output: []f32, cancelled: fn (usize): bool, context: usize
): u32 {
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 1;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return 1;
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var column: usize = 0;
            while column < width {
                const offset = (row * width + column) * 3;
                var channel_index: usize = 0;
                while channel_index < 3 {
                    const value = input[offset + channel_index];
                    if not core.finite_sample(value) or value < -16.0
                    or value > 16.0 {
                        return 2;
                    }
                    if pass == 1 {
                        output[offset + channel_index] = channel(value as f64) as f32;
                    }
                    channel_index = channel_index + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
