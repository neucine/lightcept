import .engine.core.core;
import std.math;

// Normalized camera-linear Bayer highlight reconstruction v1. A clipped site
// can extend a same-phase, unclipped two-sample rising slope toward that site.
// Unsupported clipped plateaus remain at their measured value.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct HighlightAsset {
    pub version: u32;
    pub cfa: [4]u32;
    pub clip_threshold: f64;
    pub maximum_value: f64;
    pub maximum_change: f64;
}

pub fn valid(asset: HighlightAsset): bool {
    var counts: [3]u32 = [0, 0, 0];
    var phase: usize = 0;
    while phase < 4 {
        if asset.cfa[phase] > 2 {
            return false;
        }
        const color = asset.cfa[phase] as usize;
        counts[color] = counts[color] + 1;
        phase = phase + 1;
    }
    return asset.version == algorithm_version
    and counts[0] == 1 and counts[1] == 2 and counts[2] == 1
    and ((asset.cfa[0] == 1 and asset.cfa[3] == 1)
        or (asset.cfa[1] == 1 and asset.cfa[2] == 1)
    )
    and asset.clip_threshold >= 0.9 and asset.clip_threshold <= 1.0
    and asset.maximum_value >= 1.0 and asset.maximum_value <= 8.0
    and asset.maximum_change >= 0.0 and asset.maximum_change <= 2.0;
}

fn candidate(input: []const f32, clip: []const u8, width: usize,
    x: usize, y: usize, dx: i32, dy: i32, asset: HighlightAsset
): f64 {
    var near_x = x;
    var near_y = y;
    var far_x = x;
    var far_y = y;
    if dx < 0 {
        if x < 4 {
            return 0.0;
        }
        near_x = x - 2;
        far_x = x - 4;
    } else if dx > 0 {
        near_x = x + 2;
        far_x = x + 4;
    }
    if dy < 0 {
        if y < 4 {
            return 0.0;
        }
        near_y = y - 2;
        far_y = y - 4;
    } else if dy > 0 {
        near_y = y + 2;
        far_y = y + 4;
    }
    const near_index = near_y * width + near_x;
    const far_index = far_y * width + far_x;
    if clip[near_index] != 0 or clip[far_index] != 0 {
        return 0.0;
    }
    const near = input[near_index] as f64;
    const far = input[far_index] as f64;
    if near <= far {
        return 0.0;
    }
    const estimate = 2.0 * near - far;
    if estimate < asset.clip_threshold {
        return 0.0;
    }
    return estimate;
}

fn reconstructed(input: []const f32, clip: []const u8,
    width: usize, height: usize, x: usize, y: usize,
    asset: HighlightAsset
): ?f32 {
    const index = y * width + x;
    if clip[index] == 0 or asset.maximum_change == 0.0 {
        return input[index];
    }
    var sum: f64 = 0.0;
    var count: f64 = 0.0;
    if x >= 4 {
        const value = candidate(input, clip, width, x, y, -1, 0, asset);
        if value > 0.0 {
            sum = sum + value;
            count = count + 1.0;
        }
    }
    if x < width and width - x > 4 {
        const value = candidate(input, clip, width, x, y, 1, 0, asset);
        if value > 0.0 {
            sum = sum + value;
            count = count + 1.0;
        }
    }
    if y >= 4 {
        const value = candidate(input, clip, width, x, y, 0, -1, asset);
        if value > 0.0 {
            sum = sum + value;
            count = count + 1.0;
        }
    }
    if y < height and height - y > 4 {
        const value = candidate(input, clip, width, x, y, 0, 1, asset);
        if value > 0.0 {
            sum = sum + value;
            count = count + 1.0;
        }
    }
    if count == 0.0 {
        return input[index];
    }
    var result = sum / count;
    const center = input[index] as f64;
    if result < center {
        result = center;
    }
    if result > asset.maximum_value {
        result = asset.maximum_value;
    }
    if result > center + asset.maximum_change {
        result = center + asset.maximum_change;
    }
    return math.to_f32_rounded(result);
}

// Immutable row-major f32 mosaic and u8 clip evidence, disjoint f32 output.
// Clip values must be 0 or 1 and match the threshold. A four-pixel halo is
// needed. Status 0 success, 1 asset, 2 shape/limit, 3 invalid input,
// 4 invalid clip evidence, 5 nonfinite result, 7 cancelled. Any nonzero
// status invalidates output, including partial writes after cancellation.
pub fn apply(input: []const f32, clip: []const u8,
    width: usize, height: usize, asset: HighlightAsset, output: []f32,
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
    if input.len() != pixels or clip.len() != pixels or output.len() != pixels {
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
                    const value = input[index] as f64;
                    if not core.finite_sample(input[index]) or value < 0.0
                    or value > 1.0 {
                        return 3;
                    }
                    if clip[index] > 1 or (clip[index] == 1
                        and value < asset.clip_threshold
                    )
                    or (clip[index] == 0 and value >= asset.clip_threshold) {
                        return 4;
                    }
                } else {
                    const reconstructed_value = reconstructed(input, clip, width, height, x, y, asset);
                    if reconstructed_value is value {
                        if pass == 1 {
                            if not core.finite_sample(value) {
                                return 5;
                            }
                        } else {
                            output[index] = value;
                        }
                    } else {
                        return 5;
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
