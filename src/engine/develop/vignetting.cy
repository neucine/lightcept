import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 lens vignetting correction v1. The caller owns
// the calibration and source-stage identity carried by model_hash.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct VignettingAsset {
    pub version: u32;
    pub model_hash: u64;
    pub center_x_fraction: f64;
    pub center_y_fraction: f64;
    pub k1: f64;
    pub k2: f64;
    pub k3: f64;
    pub strength: f64;
    pub maximum_gain: f64;
}

pub fn valid(asset: VignettingAsset): bool {
    return asset.version == algorithm_version and asset.model_hash != 0
    and asset.center_x_fraction >= 0.25 and asset.center_x_fraction <= 0.75
    and asset.center_y_fraction >= 0.25 and asset.center_y_fraction <= 0.75
    and asset.k1 >= -0.25 and asset.k1 <= 0.25
    and asset.k2 >= -0.25 and asset.k2 <= 0.25
    and asset.k3 >= -0.25 and asset.k3 <= 0.25
    and asset.strength >= 0.0 and asset.strength <= 1.0
    and asset.maximum_gain >= 1.0 and asset.maximum_gain <= 4.0;
}

// Radius 1 reaches the farthest image corner from the declared optical center.
// The denominator remains at least 0.25 for the accepted coefficient range.
pub fn gain(width: usize, height: usize, asset: VignettingAsset,
    x: usize, y: usize
): f64 {
    if not valid(asset) or width < 2 or height < 2
    or width > maximum_pixels or height > maximum_pixels / width
    or x >= width or y >= height {
        return 0.0;
    }
    const cx = ((width - 1) as f64) * asset.center_x_fraction;
    const cy = ((height - 1) as f64) * asset.center_y_fraction;
    var far_x = cx;
    var far_y = cy;
    if (width - 1) as f64 - cx > far_x {
        far_x = (width - 1) as f64 - cx;
    }
    if (height - 1) as f64 - cy > far_y {
        far_y = (height - 1) as f64 - cy;
    }
    const dx = (x as f64) - cx;
    const dy = (y as f64) - cy;
    const radius_squared = (dx * dx + dy * dy)
    / (far_x * far_x + far_y * far_y);
    const r4 = radius_squared * radius_squared;
    const r6 = r4 * radius_squared;
    const falloff = 1.0 + asset.k1 * radius_squared
    + asset.k2 * r4 + asset.k3 * r6;
    var modeled = 1.0 / falloff;
    if modeled > asset.maximum_gain {
        modeled = asset.maximum_gain;
    }
    if modeled < 1.0 / asset.maximum_gain {
        modeled = 1.0 / asset.maximum_gain;
    }
    return 1.0 + asset.strength * (modeled - 1.0);
}

// Immutable interleaved f32 RGB input and disjoint same-size output. No halo.
// Status 0 success, 1 asset, 2 shape/limit, 3 nonfinite input, 4 nonfinite
// f32 result, 7 cancelled. Input and projected output are checked before
// writing; any failure invalidates output, including partial writes.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: VignettingAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width < 2 or height < 2 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return 2;
    }
    var pass: usize = 0;
    while pass < 3 {
        var y: usize = 0;
        while y < height {
            if cancelled(context) {
                return 7;
            }
            var x: usize = 0;
            while x < width {
                const index = (y * width + x) * 3;
                const factor = gain(width, height, asset, x, y);
                var channel: usize = 0;
                while channel < 3 {
                    if pass == 0 {
                        if not core.finite_sample(input[index + channel]) {
                            return 3;
                        }
                    } else {
                        const rounded = math.to_f32_rounded(
                            (input[index + channel] as f64) * factor
                        );
                        if rounded is value {
                            if pass == 1 {
                                if not core.finite_sample(value) {
                                    return 4;
                                }
                            } else {
                                output[index + channel] = value;
                            }
                        } else {
                            return 4;
                        }
                    }
                    channel = channel + 1;
                }
                x = x + 1;
            }
            y = y + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
