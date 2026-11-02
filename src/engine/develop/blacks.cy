import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 black toe v1. This is a bounded luminance
// offset that decays smoothly to zero at the declared middle-gray pivot.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
pub const middle_gray: f64 = 0.18;

pub struct BlacksAsset {
    pub version: u32;
    // Positive values deepen the toe; linear reference-white units.
    pub offset: f64;
}

pub fn valid(asset: BlacksAsset): bool {
    return asset.version == algorithm_version
    and asset.offset >= -0.125 and asset.offset <= 0.125;
}

pub fn toe_weight(y: f64): f64 {
    if y <= 0.0 {
        return 1.0;
    }
    if y >= middle_gray {
        return 0.0;
    }
    const remaining = 1.0 - y / middle_gray;
    return remaining * remaining;
}

pub fn adjust(red: f64, green: f64, blue: f64,
    asset: BlacksAsset
): [3]f64 {
    if asset.offset == 0.0 {
        return [red, green, blue];
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const change = asset.offset * toe_weight(y);
    return [red - change, green - change, blue - change];
}

// Immutable interleaved f32 scene-linear RGB in [-0.25,8] and disjoint
// same-shape output. Status 0 success, 1 asset, 2 shape/limit, 3 input,
// 4 projected output, 7 cancelled. Poll each row in validation and write
// passes. Any failure invalidates output. No halo or output gamut clipping.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: BlacksAsset, output: []f32,
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
                const result = adjust(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64,
                    asset
                );
                channel = 0;
                while channel < 3 {
                    if not (result[channel] >= -8.125
                        and result[channel] <= 8.125
                    ) {
                        return 4;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(result[channel]);
                        if rounded is value {
                            output[offset + channel] = value;
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
