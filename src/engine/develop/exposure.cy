import .engine.core.core;
import std.math;

// Signed scene-linear exposure multiplication; gain = 2^EV.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct ExposureAsset {
    pub version: u32;
    // Camera baseline plus user exposure, in EV stops [-16,16].
    pub ev: f64;
}

pub fn valid(asset: ExposureAsset): bool {
    return asset.version == algorithm_version
    and asset.ev >= -16.0 and asset.ev <= 16.0;
}
pub fn apply(value: f64, gain: f64): f64 {
    return value * gain;
}

// Camera baseline and user exposure are additive EV offsets.
pub fn compose(default_ev: f64, user_ev: f64): f64 {
    return (default_ev as f64 + user_ev as f64) as f64;
}

// Immutable interleaved scene-linear Rec.2020/D65 f32 RGB in [-0.25,8],
// disjoint output in [-16384,524288] linear reference-white units. Two passes
// validate before writing; cancellation is polled each row. Status 0 success,
// 1 asset, 2 geometry/limit, 3 source, 4 result, 7 cancellation. A nonzero
// status invalidates all output. No halo, clipping or display transfer.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: ExposureAsset, output: []f32,
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
    const gain = math.pow_f64(2.0, asset.ev);
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
                    const source = input[offset + channel];
                    if not core.finite_sample(source) or source < -0.25
                    or source > 8.0 {
                        return 3;
                    }
                    const value = apply(source as f64, gain);
                    if not (value >= -16384.0 and value <= 524288.0) {
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
