import .engine.core.core;
import std.math;

// D65 scene-linear Rec.2020 to D65 linear sRGB v1. No gamut clip or transfer.
// Coefficients match the current fixed sRGB output path's pinned matrix.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub fn convert(red: f64, green: f64, blue: f64): [3]f64 {
    return [1.660491 * red - 0.587641 * green - 0.072850 * blue,
        -0.124550 * red + 1.132900 * green - 0.008349 * blue,
        -0.018151 * red - 0.100579 * green + 1.118730 * blue
    ];
}

// Immutable row-major interleaved f32 Rec.2020 RGB in [-0.25,8] and
// disjoint same-shaped linear-sRGB f32 output. Status 0 success, 1 shape or
// limit, 2 invalid input, 3 invalid result, 7 cancelled. Poll before each
// row in both passes. Any failure invalidates output. No spatial halo.
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
                var channel: usize = 0;
                while channel < 3 {
                    const value = input[offset + channel];
                    if not core.finite_sample(value) or value < -0.25
                    or value > 8.0 {
                        return 2;
                    }
                    channel = channel + 1;
                }
                const converted = convert(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64
                );
                channel = 0;
                while channel < 3 {
                    if not (converted[channel] >= -16.0
                        and converted[channel] <= 16.0
                    ) {
                        return 3;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(converted[channel]);
                        if rounded is value {
                            output[offset + channel] = value;
                        } else {
                            return 3;
                        }
                    }
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
