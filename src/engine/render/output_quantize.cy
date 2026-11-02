import .engine.core.core;
import std.math;

// Encoded sRGB to integer RGB quantization v1. Round to nearest, with exact
// half-step ties rounded upward on the nonnegative input domain. No dither.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub fn channel8(encoded: f64): u8 {
    return math.round_f64(encoded * 255.0) as u8;
}

pub fn channel16(encoded: f64): u16 {
    return math.round_f64(encoded * 65535.0) as u16;
}

fn shape(input_len: usize, output_len: usize,
    width: usize, height: usize
): bool {
    return width > 0 and height > 0 and width <= maximum_pixels
    and height <= maximum_pixels / width
    and input_len == width * height * 3
    and output_len == input_len;
}

// Immutable row-major interleaved f32 encoded sRGB input and disjoint u8 RGB
// output. Status 0 success, 1 shape/limit, 2 nonfinite or out-of-domain input,
// 7 cancelled. Poll before each row in both passes. Validate all input before
// writes. Any failed output is invalid, including partial writes. No halo.
pub fn apply8(input: []const f32, width: usize, height: usize,
    output: []u8, cancelled: fn (usize): bool, context: usize
): u32 {
    if not shape(input.len(), output.len(), width, height) {
        return 1;
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var channel: usize = 0;
            while channel < width * 3 {
                const index = row * width * 3 + channel;
                const value = input[index];
                if not core.finite_sample(value) or value < 0.0
                or value > 1.0 {
                    return 2;
                }
                if pass == 1 {
                    output[index] = channel8(value as f64);
                }
                channel = channel + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}

// Same contract with u16 RGB output. The caller owns endianness and packing.
pub fn apply16(input: []const f32, width: usize, height: usize,
    output: []u16, cancelled: fn (usize): bool, context: usize
): u32 {
    if not shape(input.len(), output.len(), width, height) {
        return 1;
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var channel: usize = 0;
            while channel < width * 3 {
                const index = row * width * 3 + channel;
                const value = input[index];
                if not core.finite_sample(value) or value < 0.0
                or value > 1.0 {
                    return 2;
                }
                if pass == 1 {
                    output[index] = channel16(value as f64);
                }
                channel = channel + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
