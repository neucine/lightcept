import .engine.core.core;
import std.math;

// Normalized camera-linear Bayer mosaic denoise v1. The four CFA phases are
// filtered independently, before demosaic. Values above reference white remain
// valid; the caller supplies sensor-characterized noise scales.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct SensorNoiseAsset {
    pub version: u32;
    pub cfa: [4]u32;
    pub read_sigma: [3]f64;
    pub shot_variance: [3]f64;
    pub strength: f64;
    pub maximum_change: f64;
}

pub fn valid(asset: SensorNoiseAsset): bool {
    if asset.version != algorithm_version
    or not (asset.strength >= 0.0 and asset.strength <= 1.0)
    or not (asset.maximum_change >= 0.0 and asset.maximum_change <= 0.5) {
        return false;
    }
    var red: usize = 0;
    var green: usize = 0;
    var blue: usize = 0;
    var phase: usize = 0;
    while phase < 4 {
        if asset.cfa[phase] == 0 {
            red = red + 1;
        } else if asset.cfa[phase] == 1 {
            green = green + 1;
        } else if asset.cfa[phase] == 2 {
            blue = blue + 1;
        } else {
            return false;
        }
        phase = phase + 1;
    }
    if red != 1 or green != 2 or blue != 1 {
        return false;
    }
    if not ((asset.cfa[0] == 1 and asset.cfa[3] == 1)
        or (asset.cfa[1] == 1 and asset.cfa[2] == 1)
    ) {
        return false;
    }
    var channel: usize = 0;
    while channel < 3 {
        if not (asset.read_sigma[channel] >= 0.000001 and asset.read_sigma[channel] <= 0.5)
        or not (asset.shot_variance[channel] >= 0.0 and asset.shot_variance[channel] <= 0.25) {
            return false;
        }
        channel = channel + 1;
    }
    return true;
}

fn filtered(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, asset: SensorNoiseAsset
): ?f32 {
    const index = y * width + x;
    const center = input[index] as f64;
    if asset.strength == 0.0 or asset.maximum_change == 0.0 {
        return input[index];
    }
    const color = asset.cfa[(y % 2) * 2 + x % 2] as usize;
    const sigma = asset.read_sigma[color];
    var signal: f64 = 0.0;
    if center > 0.0 {
        signal = center;
    }
    const variance = sigma * sigma + asset.shot_variance[color] * signal;
    var sum: f64 = center * 4.0;
    var weights: f64 = 4.0;
    var dy: i32 = -1;
    while dy <= 1 {
        var dx: i32 = -1;
        while dx <= 1 {
            if dx != 0 or dy != 0 {
                // Skipping outside samples preserves CFA phase at every border.
                const valid_x = (dx >= 0 or x >= 2) and (dx <= 0 or x + 2 < width);
                const valid_y = (dy >= 0 or y >= 2) and (dy <= 0 or y + 2 < height);
                if valid_x and valid_y {
                    var neighbor_x = x;
                    var neighbor_y = y;
                    if dx < 0 {
                        neighbor_x = x - 2;
                    } else if dx > 0 {
                        neighbor_x = x + 2;
                    }
                    if dy < 0 {
                        neighbor_y = y - 2;
                    } else if dy > 0 {
                        neighbor_y = y + 2;
                    }
                    const value = input[neighbor_y * width + neighbor_x] as f64;
                    const difference = value - center;
                    const range_weight = 1.0 / (1.0 + difference * difference / variance);
                    var spatial_weight: f64 = 1.0;
                    if dx == 0 or dy == 0 {
                        spatial_weight = 2.0;
                    }
                    const weight = range_weight * spatial_weight;
                    sum = sum + value * weight;
                    weights = weights + weight;
                }
            }
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    var change = asset.strength * (sum / weights - center);
    if change > asset.maximum_change {
        change = asset.maximum_change;
    }
    if change < -asset.maximum_change {
        change = -asset.maximum_change;
    }
    return math.to_f32_rounded(center + change);
}

// Input/output are disjoint row-major f32 mosaics with the CFA phase at (0,0).
// Status: 0 success, 1 invalid asset, 2 shape/limit, 3 nonfinite input,
// 4 nonfinite result, 7 cancelled. A failed or cancelled output is invalid.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: SensorNoiseAsset, output: []f32,
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
    if input.len() != pixels or output.len() != pixels {
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
                const index = y * width + x;
                if pass == 0 {
                    if not core.finite_sample(input[index]) {
                        return 3;
                    }
                } else {
                    const filtered_value = filtered(input, width, height, x, y, asset);
                    if filtered_value is value {
                        if pass == 1 {
                            if not core.finite_sample(value) {
                                return 4;
                            }
                        } else {
                            output[index] = value;
                        }
                    } else {
                        return 4;
                    }
                }
                x = x + 1;
            }
            y = y + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
