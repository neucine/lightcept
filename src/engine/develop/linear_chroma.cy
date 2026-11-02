import .engine.core.core;
import std.math;

// Scene-linear Rec.2020 luminance coefficients (BT.2020/D65). This operation
// retains signed values and highlight headroom; output encoding clips later.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct LinearChromaAsset {
    pub version: u32;
    // Dimensionless chroma factor in [0,2], neutral 1.
    pub factor: f64;
}

pub fn valid(asset: LinearChromaAsset): bool {
    return asset.version == algorithm_version
    and asset.factor >= 0.0 and asset.factor <= 2.0;
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

pub fn apply_native(red: f64, green: f64, blue: f64, factor: f64): NativeRgb {
    if factor == 1.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    return {
        red: y + factor * (red - y),
        green: y + factor * (green - y),
        blue: y + factor * (blue - y)
    };
}

pub fn apply(red: f64, green: f64, blue: f64, factor: f64): LinearRgb {
    const result = apply_native(red as f64, green as f64, blue as f64, factor as f64);
    return {
        red: result.red as f64,
        green: result.green as f64,
        blue: result.blue as f64,
    };
}

// Immutable scene-linear Rec.2020/D65 f32 RGB in [-0.25,8], disjoint
// output in [-16,16] reference-white units. No gamut clipping or halo.
// Status 0 success, 1 asset, 2 shape/limit, 3 input, 4 result, 7 cancelled.
// Two passes poll each row and validate projected values before writes.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: LinearChromaAsset, output: []f32,
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
                    asset.factor
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
