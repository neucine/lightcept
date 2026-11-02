import .engine.core.core;
import .engine.color.output_color;
import .engine.color.working_to_linear_srgb;
import std.math;

// Fixed sRGB reference view transform v1. Scene-linear Rec.2020/D65 RGB
// becomes encoded, view-referred sRGB. Scene 1 maps to reference white;
// scene values outside display range clip without a photographic tone curve.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
pub const display_srgb_iec61966_2_1: u32 = 1;
pub const transfer_srgb: u32 = 1;

pub struct ReferenceDisplay {
    pub version: u32;
    pub display: u32;
    pub transfer: u32;
    // cd/m² (nits), D65 CIE 1931 xy, and BT.709 primary xy.
    pub white_nits: f64;
    pub black_nits: f64;
    pub white_x: f64;
    pub white_y: f64;
    pub red_x: f64;
    pub red_y: f64;
    pub green_x: f64;
    pub green_y: f64;
    pub blue_x: f64;
    pub blue_y: f64;
}

pub struct ViewReport {
    // 0 success, 1 display contract, 2 shape/limit, 3 input,
    // 4 encoded output, 7 cancelled. Nonzero status invalidates all fields.
    pub status: u32;
    pub version: u32;
    pub display: u32;
    pub pixels: usize;
    pub clipped_pixels: usize;
}

pub fn srgb_reference(): ReferenceDisplay {
    return {
        version: algorithm_version,
        display: display_srgb_iec61966_2_1,
        transfer: transfer_srgb,
        white_nits: 80.0,
        black_nits: 0.2,
        white_x: 0.3127,
        white_y: 0.3290,
        red_x: 0.64,
        red_y: 0.33,
        green_x: 0.30,
        green_y: 0.60,
        blue_x: 0.15,
        blue_y: 0.06
    };
}

pub fn valid(reference: ReferenceDisplay): bool {
    const fixed = srgb_reference();
    return reference.version == fixed.version and reference.display == fixed.display
    and reference.transfer == fixed.transfer
    and reference.white_nits == fixed.white_nits
    and reference.black_nits == fixed.black_nits
    and reference.white_x == fixed.white_x and reference.white_y == fixed.white_y
    and reference.red_x == fixed.red_x and reference.red_y == fixed.red_y
    and reference.green_x == fixed.green_x and reference.green_y == fixed.green_y
    and reference.blue_x == fixed.blue_x and reference.blue_y == fixed.blue_y;
}

fn failure(status: u32): ViewReport {
    return {
        status: status,
        version: algorithm_version,
        display: 0,
        pixels: 0,
        clipped_pixels: 0
    };
}

// Immutable interleaved scene RGB f32 in [-0.25,8], disjoint same-shape
// encoded view RGB f32 in [0,1]. Two passes validate before writes. Clipped
// pixel count refers to destination-linear sRGB before transfer. Poll every
// row in both passes; any failure invalidates the output and count. No halo.
pub fn apply(input: []const f32, width: usize, height: usize,
    reference: ReferenceDisplay, output: []f32,
    cancelled: fn (usize): bool, context: usize
): ViewReport {
    if not valid(reference) {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(2);
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return failure(2);
    }
    var clipped_pixels: usize = 0;
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return failure(7);
            }
            var column: usize = 0;
            while column < width {
                const offset = (row * width + column) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    const sample = input[offset + channel];
                    if not core.finite_sample(sample) or sample < -0.25
                    or sample > 8.0 {
                        return failure(3);
                    }
                    channel = channel + 1;
                }
                const red = input[offset] as f64;
                const green = input[offset + 1] as f64;
                const blue = input[offset + 2] as f64;
                const linear = working_to_linear_srgb.convert(red, green, blue);
                if pass == 0 and (linear[0] < 0.0 or linear[0] > 1.0
                    or linear[1] < 0.0 or linear[1] > 1.0
                    or linear[2] < 0.0 or linear[2] > 1.0
                ) {
                    clipped_pixels = clipped_pixels + 1;
                }
                channel = 0;
                while channel < 3 {
                    const encoded = output_color.encode_channel(red, green, blue, channel as i32);
                    if not (encoded >= 0.0 and encoded <= 1.0) {
                        return failure(4);
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(encoded);
                        if rounded is value {
                            output[offset + channel] = value;
                        } else {
                            return failure(4);
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
    return {
        status: 0,
        version: algorithm_version,
        display: reference.display,
        pixels: pixels,
        clipped_pixels: clipped_pixels
    };
}
