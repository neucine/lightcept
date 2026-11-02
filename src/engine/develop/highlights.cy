import .engine.core.core;
import std.math;

// Diagnostic pointwise scene-linear highlight band v1. Input/output: signed
// Rec.2020/D65 RGB. The adjustment is confined to luminance (0.18, 1),
// retains both endpoints and headroom above reference white, and preserves
// absolute channel differences. It is not highlight reconstruction.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct HighlightsAsset {
    pub version: u32;
    pub strength: f64;
}

pub fn valid(asset: HighlightsAsset): bool {
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

pub fn apply(red: f64, green: f64, blue: f64, strength: f64): LinearRgb {
    if strength == 0.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    if y <= 0.18 or y >= 1.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const span = 1.0 - 0.18;
    const position = (y - 0.18) / span;
    const offset = strength * span * position * (1.0 - position);
    return {
        red: (red + offset),
        green: (green + offset),
        blue: (blue + offset)
    };
}

// Immutable interleaved scene-linear Rec.2020/D65 f32 RGB in [-0.25,8],
// disjoint output in [-0.5,8.5] reference-white units. Two passes validate
// all source/projected values before writes, polling cancellation per row.
// Status 0 success, 1 asset, 2 shape/limit, 3 input, 4 result, 7 cancelled.
// Nonzero status invalidates all output. No halo or sensor reconstruction.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: HighlightsAsset, output: []f32,
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
                    if not (value >= -0.5 and value <= 8.5) {
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
