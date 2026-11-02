import .engine.core.core;
import std.math;

// IEC sRGB component encoding v1. Input is clipped D65 linear sRGB [0,1].
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub fn encode(linear: f64): f64 {
    if linear == 0.0 or linear == 1.0 {
        return linear;
    }
    if linear <= 0.0031308 {
        return 12.92 * linear;
    }
    return 1.055 * math.pow_f64(linear, 0.4166666666666667) - 0.055;
}

// Immutable row-major interleaved f32 linear-sRGB input and disjoint encoded
// f32 output. Status 0 success, 1 shape/limit, 2 out-of-domain input,
// 3 invalid output, 7 cancelled. Validate projected output before writes;
// poll each row in both passes. Any failed output is invalid. No halo.
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
                    if not core.finite_sample(value) or value < 0.0
                    or value > 1.0 {
                        return 2;
                    }
                    const encoded = encode(value as f64);
                    if not (encoded >= 0.0 and encoded <= 1.0) {
                        return 3;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(encoded);
                        if rounded is result {
                            output[offset + channel_index] = result;
                        } else {
                            return 3;
                        }
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
