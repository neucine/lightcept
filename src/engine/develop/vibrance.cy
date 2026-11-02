import .engine.core.core;
import std.math;

// Diagnostic linear-working vibrance v1. Signed Rec.2020/D65 RGB is measured
// against BT.2020 luminance. Low-chroma colors receive more of the requested
// chroma change; luminance and hue direction are retained. This is not a
// perceptual-space or skin-tone-aware vibrance operator.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct VibranceAsset {
    pub version: u32;
    pub strength: f64;
}

pub fn valid(asset: VibranceAsset): bool {
    return asset.version == algorithm_version and valid_strength(asset.strength);
}
pub struct LinearRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn minimum(): f64 {
    return -1.0;
}
pub fn maximum(): f64 {
    return 1.0;
}
pub fn valid_strength(strength: f64): bool {
    return strength >= minimum() and strength <= maximum();
}

fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}
fn maximum3(a: f64, b: f64, c: f64): f64 {
    var result = a;
    if b > result {
        result = b;
    }
    if c > result {
        result = c;
    }
    return result;
}

pub fn apply(red: f64, green: f64, blue: f64, strength: f64): LinearRgb {
    if strength == 0.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const r = red;
    const g = green;
    const b = blue;
    const y = 0.2627 * r + 0.6780 * g + 0.0593 * b;
    const chroma = maximum3(absolute(r - y), absolute(g - y), absolute(b - y));
    const factor = 1.0 + strength / (1.0 + 4.0 * chroma);
    return {
        red: (y + (r - y) * factor),
        green: (y + (g - y) * factor),
        blue: (y + (b - y) * factor)
    };
}

// Immutable scene-linear Rec.2020/D65 f32 RGB in [-0.25,8], disjoint
// output in [-16,16] reference-white units. No gamut clipping or halo.
// Status 0 success, 1 asset, 2 geometry/limit, 3 input, 4 result,
// 7 cancellation. Two passes poll each row and validate projected samples
// before writes; any nonzero status invalidates all output.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: VibranceAsset, output: []f32,
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
                    asset.strength
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
