import .engine.core.core;
import .engine.color.output_color;
import .engine.render.output_quantize;

// Fused output transform v1. Immutable scene-linear Rec.2020/D65 RGB f32
// becomes encoded sRGB integer samples for the fixed sRGB2014 destination.
// Matrix, destination clip and transfer are owned by output_color; integer
// rounding by output_quantize. The caller attaches ICC and packages bytes.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

fn shape(input_len: usize, output_len: usize, width: usize,
    height: usize, output_channels: usize
): bool {
    return width > 0 and height > 0 and width <= maximum_pixels
    and height <= maximum_pixels / width
    and input_len == width * height * 3
    and output_len == width * height * output_channels;
}

fn valid_input(input: []const f32, width: usize, height: usize,
    cancelled: fn (usize): bool, context: usize
): u32 {
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var channel: usize = row * width * 3;
        while channel < (row + 1) * width * 3 {
            const value = input[channel];
            if not core.finite_sample(value) or value < -0.25
            or value > 8.0 {
                return 2;
            }
            channel = channel + 1;
        }
        row = row + 1;
    }
    return 0;
}

// RGB16 output has interleaved visual top-left row-major channel order.
// The caller owns byte order and file encoding. Status 0 success, 1 shape
// or limit, 2 invalid input, 3 invalid encoded value, 7 cancelled. Validate
// all input before writes; poll at each row in both passes. Any nonzero
// status invalidates the entire output, including a partially written frame.
pub fn rgb16(input: []const f32, width: usize, height: usize,
    output: []u16, cancelled: fn (usize): bool, context: usize
): u32 {
    if not shape(input.len(), output.len(), width, height, 3) {
        return 1;
    }
    const status = valid_input(input, width, height, cancelled, context);
    if status != 0 {
        return status;
    }
    var row: usize = 0;
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
            var channel: usize = 0;
            while channel < 3 {
                const encoded = output_color.encode_channel(red, green, blue, channel as i32);
                if not (encoded >= 0.0 and encoded <= 1.0) {
                    return 3;
                }
                output[offset + channel] = output_quantize.channel16(encoded);
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}

// RGBA8 has encoded sRGB channels and opaque alpha=255. Same input, extent,
// error, cancellation and invalid-partial-output contract as rgb16.
pub fn rgba8(input: []const f32, width: usize, height: usize,
    output: []u8, cancelled: fn (usize): bool, context: usize
): u32 {
    if not shape(input.len(), output.len(), width, height, 4) {
        return 1;
    }
    const status = valid_input(input, width, height, cancelled, context);
    if status != 0 {
        return status;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const source = (row * width + column) * 3;
            const target = (row * width + column) * 4;
            const red = input[source] as f64;
            const green = input[source + 1] as f64;
            const blue = input[source + 2] as f64;
            var channel: usize = 0;
            while channel < 3 {
                const encoded = output_color.encode_channel(red, green, blue, channel as i32);
                if not (encoded >= 0.0 and encoded <= 1.0) {
                    return 3;
                }
                output[target + channel] = output_quantize.channel8(encoded);
                channel = channel + 1;
            }
            output[target + 3] = 255;
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
