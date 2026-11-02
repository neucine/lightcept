import .engine.color.output_color;
import .engine.core.core;
import std.math;

// Diagnostic scene-linear Rec.2020/D65 channel mixer v1. The six stored
// cross-channel coefficients imply each row's diagonal coefficient. Computing
// with channel differences keeps every neutral RGB triplet exactly neutral.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct MixerAsset {
    pub version: u32;
    pub red_from_green: f64;
    pub red_from_blue: f64;
    pub green_from_red: f64;
    pub green_from_blue: f64;
    pub blue_from_red: f64;
    pub blue_from_green: f64;
}

pub struct MixerResult {
    pub valid: bool;
    // 0 success, 1 invalid asset, 2 nonfinite input, 3 nonfinite output.
    pub status: u32;
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

fn finite(value: f64): bool {
    const infinity = output_color.exposure_gain_native(1024.0);
    return value > -infinity and value < infinity;
}

fn bounded(value: f64): bool {
    return value >= -1.0 and value <= 1.0;
}

pub fn neutral_asset(): MixerAsset {
    return {
        version: algorithm_version,
        red_from_green: 0.0,
        red_from_blue: 0.0,
        green_from_red: 0.0,
        green_from_blue: 0.0,
        blue_from_red: 0.0,
        blue_from_green: 0.0
    };
}

pub fn valid(asset: MixerAsset): bool {
    return asset.version == algorithm_version
    and bounded(asset.red_from_green) and bounded(asset.red_from_blue)
    and bounded(asset.green_from_red) and bounded(asset.green_from_blue)
    and bounded(asset.blue_from_red) and bounded(asset.blue_from_green);
}

fn failure(status: u32): MixerResult {
    return {
        valid: false,
        status: status,
        red: 0.0,
        green: 0.0,
        blue: 0.0
    };
}

pub fn apply(asset: MixerAsset, red: f64, green: f64, blue: f64): MixerResult {
    if not valid(asset) {
        return failure(1);
    }
    if not (finite(red) and finite(green) and finite(blue)) {
        return failure(2);
    }
    const result: MixerResult = {
        valid: true,
        status: 0,
        red: red + asset.red_from_green * (green - red) + asset.red_from_blue * (blue - red),
        green: green + asset.green_from_red * (red - green) + asset.green_from_blue * (blue - green),
        blue: blue + asset.blue_from_red * (red - blue) + asset.blue_from_green * (green - blue)
    };
    if not (finite(result.red) and finite(result.green) and finite(result.blue)) {
        return failure(3);
    }
    return result;
}

// Immutable interleaved scene-linear Rec.2020/D65 f32 RGB in [-0.25,8],
// disjoint output in [-32,32] linear reference-white units. Six bounded
// coefficients imply row sums of one; neutral RGB stays neutral. No gamut
// clipping or halo. Status 0 success, 1 asset, 2 shape/limit, 3 input,
// 4 result, 7 cancellation. Two passes validate before writing and poll
// cancellation per row. Nonzero invalidates all output.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: MixerAsset, output: []f32,
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
                const result = apply(asset, input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64
                );
                if result.status != 0 {
                    return 4;
                }
                const values: [3]f64 = [result.red, result.green, result.blue];
                channel = 0;
                while channel < 3 {
                    const value = values[channel];
                    if not (value >= -32.0 and value <= 32.0) {
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
