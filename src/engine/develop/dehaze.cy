import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 atmospheric inversion v1. The caller owns the
// provenance of the transmission field and atmospheric-light estimate.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct HazeAsset {
    pub version: u32;
    pub atmospheric_light: [3]f64;
    pub minimum_transmission: f64;
    pub strength: f64;
    pub maximum_change: f64;
}

pub fn valid(asset: HazeAsset): bool {
    if asset.version != algorithm_version
    or not (asset.minimum_transmission >= 0.05 and asset.minimum_transmission <= 1.0)
    or not (asset.strength >= 0.0 and asset.strength <= 1.0)
    or not (asset.maximum_change >= 0.0 and asset.maximum_change <= 2.0) {
        return false;
    }
    var channel: usize = 0;
    while channel < 3 {
        if not (asset.atmospheric_light[channel] >= 0.0
            and asset.atmospheric_light[channel] <= 4.0
        ) {
            return false;
        }
        channel = channel + 1;
    }
    return true;
}

fn adjusted(input: f32, transmission: f32, channel: usize, asset: HazeAsset): ?f32 {
    if asset.strength == 0.0 or asset.maximum_change == 0.0
    or transmission == 1.0 {
        return input;
    }
    const effective = 1.0 - asset.strength * (1.0 - (transmission as f64));
    const center = input as f64;
    var change = (center - asset.atmospheric_light[channel]) / effective
    + asset.atmospheric_light[channel] - center;
    if change > asset.maximum_change {
        change = asset.maximum_change;
    }
    if change < -asset.maximum_change {
        change = -asset.maximum_change;
    }
    return math.to_f32_rounded(center + change);
}

// Immutable interleaved RGB, one transmission f32 per pixel, and disjoint
// caller-owned output. Transmission is in [minimum_transmission,1], where 1
// means clear air. Status: 0 success, 1 asset, 2 shape/limit, 3 nonfinite
// input, 4 invalid transmission, 5 nonfinite result, 7 cancelled. All input
// and projected output is validated before writes; any failure invalidates
// output, including partial writes after cancellation.
pub fn apply(input: []const f32, transmission: []const f32,
    width: usize, height: usize, asset: HazeAsset, output: []f32,
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
    if input.len() != pixels * 3 or transmission.len() != pixels
    or output.len() != pixels * 3 {
        return 2;
    }
    var pass: usize = 0;
    while pass < 3 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var column: usize = 0;
            while column < width {
                const pixel = row * width + column;
                const index = pixel * 3;
                if pass == 0 {
                    const t = transmission[pixel] as f64;
                    if not (t >= asset.minimum_transmission and t <= 1.0) {
                        return 4;
                    }
                }
                var channel: usize = 0;
                while channel < 3 {
                    if pass == 0 {
                        if not core.finite_sample(input[index + channel]) {
                            return 3;
                        }
                    } else {
                        const adjusted_value = adjusted(input[index + channel], transmission[pixel],
                            channel, asset
                        );
                        if adjusted_value is value {
                            if pass == 1 {
                                if not core.finite_sample(value) {
                                    return 5;
                                }
                            } else {
                                output[index + channel] = value;
                            }
                        } else {
                            return 5;
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
