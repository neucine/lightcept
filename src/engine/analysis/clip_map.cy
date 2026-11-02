import .engine.core.core;

// Scene-linear Rec.2020/D65 RGB clip-threshold map v1. One output byte per
// pixel: bit 0 red, bit 1 green, bit 2 blue. A set bit means channel >= the
// caller's scene-linear white reference, not proven sensor saturation.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub fn channel_bits(red: f64, green: f64, blue: f64, white_reference: f64): u8 {
    var bits: u8 = 0;
    if red >= white_reference {
        bits = bits | 1;
    }
    if green >= white_reference {
        bits = bits | 2;
    }
    if blue >= white_reference {
        bits = bits | 4;
    }
    return bits;
}

// Input and output are caller-owned, disjoint buffers. No source is mutated.
// Shape: 1..maximum_pixels pixels, RGB interleaved f32 input in [-0.25,8],
// one u8 per pixel. Status: 0 success, 1 invalid reference, 2 shape/limit,
// 3 invalid input, 7 cancelled. Validation completes before output writes.
// On cancellation the output may be partial and must be discarded. Poll each
// row during validation and output.
pub fn build(input: []const f32, width: usize, height: usize, white_reference: f64,
    output: []u8, cancelled: fn (usize): bool, context: usize
): u32 {
    if not (white_reference >= 0.5 and white_reference <= 8.0) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels {
        return 2;
    }
    var pixel: usize = 0;
    while pixel < pixels {
        if pixel % width == 0 and cancelled(context) {
            return 7;
        }
        const index = pixel * 3;
        if not (core.finite_sample(input[index]) and input[index] >= -0.25
            and input[index] <= 8.0
            and core.finite_sample(input[index + 1]) and input[index + 1] >= -0.25
            and input[index + 1] <= 8.0
            and core.finite_sample(input[index + 2]) and input[index + 2] >= -0.25
            and input[index + 2] <= 8.0
        ) {
            return 3;
        }
        pixel = pixel + 1;
    }
    if cancelled(context) {
        return 7;
    }
    pixel = 0;
    while pixel < pixels {
        if pixel % width == 0 and cancelled(context) {
            return 7;
        }
        const index = pixel * 3;
        output[pixel] = channel_bits(input[index] as f64, input[index + 1] as f64,
            input[index + 2] as f64, white_reference
        );
        pixel = pixel + 1;
    }
    return 0;
}
