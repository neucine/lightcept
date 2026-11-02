import .engine.core.core;
import std.math;

// Diagnostic scene-linear contrast v1. The input is signed Rec.2020/D65 RGB.
// A positive slope expands luminance about 18% grey; negative samples and
// values above reference white are retained. Absolute chroma is unchanged.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct ContrastAsset {
    pub version: u32;
    // Dimensionless luminance slope in [0.5,2], neutral 1.
    pub slope: f64;
}

pub fn valid(asset: ContrastAsset): bool {
    return asset.version == algorithm_version and valid_slope(asset.slope);
}
pub struct LinearRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub struct NativeRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn slope_from_percent_native(percent: f64): f64 {
    if percent < 0.0 {
        return 1.0 + percent * 0.005;
    }
    return 1.0 + percent * 0.01;
}

pub fn valid_slope(slope: f64): bool {
    return slope >= slope_min() and slope <= slope_max();
}

pub fn slope_min(): f64 {
    return 0.5;
}
pub fn slope_max(): f64 {
    return 2.0;
}

// Diagnostic product-percent translation v1. A negative percentage contracts
// luminance toward 18% grey; a positive percentage expands it. The asymmetric
// spans use the whole admissible slope range with zero as exact identity.
pub fn slope_from_percent(percent: f64): f64 {
    return slope_from_percent_native(percent as f64) as f64;
}

// Status: 0 success, 3 shape, 4 invalid percentage.
fn contrast_slope_from_percent(percent: f64, output: *f64, output_len: usize): i32 {
    if output_len as usize != 1 {
        return 3;
    }
    if not (percent >= -100.0 and percent <= 100.0) {
        return 4;
    }
    unchecked {
        *(output as! *f64) = slope_from_percent(percent);
    }
    return 0;
}

pub fn apply_native(red: f64, green: f64, blue: f64, slope: f64): NativeRgb {
    if slope == 1.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const new_y = 0.18 + slope * (y - 0.18);
    const offset = new_y - y;
    return {
        red: red + offset,
        green: green + offset,
        blue: blue + offset
    };
}

pub fn apply(red: f64, green: f64, blue: f64, slope: f64): LinearRgb {
    const result = apply_native(red as f64, green as f64, blue as f64, slope as f64);
    return {
        red: result.red as f64,
        green: result.green as f64,
        blue: result.blue as f64
    };
}

// Immutable scene-linear Rec.2020/D65 f32 RGB in [-0.25,8], disjoint
// output in [-16,16] reference-white units. No clipping or halo. Status
// 0 success, 1 asset, 2 geometry/limit, 3 input, 4 result, 7 cancellation.
// Two passes poll each row and validate projected values before writes.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: ContrastAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return 2;
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
                        return 3;
                    }
                    channel = channel + 1;
                }
                const result = apply(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64,
                    asset.slope
                );
                const values: [3]f64 = [result.red, result.green, result.blue];
                channel = 0;
                while channel < 3 {
                    const value = values[channel];
                    if not (value >= -16.0 and value <= 16.0) {
                        return 4;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(value);
                        if rounded is sample {
                            output[offset + channel] = sample;
                        } else {
                            return 4;
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
