import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 mid-frequency luminance contrast v1.
// A difference of two edge-aware low passes isolates detail between the
// declared one- and three-pixel radii; equal RGB offsets preserve color.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct ClarityAsset {
    pub version: u32;
    pub amount: f64;
    pub edge_scale_y: f64;
    pub noise_threshold_y: f64;
    pub maximum_offset_y: f64;
}

pub fn valid(asset: ClarityAsset): bool {
    return asset.version == algorithm_version
    and asset.amount >= -1.0 and asset.amount <= 2.0
    and asset.edge_scale_y >= 0.01 and asset.edge_scale_y <= 1.0
    and asset.noise_threshold_y >= 0.0 and asset.noise_threshold_y <= 0.1
    and asset.maximum_offset_y >= 0.0 and asset.maximum_offset_y <= 0.5;
}

fn coordinate(position: usize, displacement: i32, limit: usize): usize {
    if displacement < 0 {
        const magnitude = (-displacement) as usize;
        if position < magnitude {
            return 0;
        }
        return position - magnitude;
    }
    const magnitude = displacement as usize;
    if magnitude >= limit or position >= limit - magnitude {
        return limit - 1;
    }
    return position + magnitude;
}

fn luminance(input: []const f32, pixel: usize): f64 {
    const index = pixel * 3;
    return 0.2627 * (input[index] as f64)
    + 0.6780 * (input[index + 1] as f64)
    + 0.0593 * (input[index + 2] as f64);
}

fn low_pass(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, radius: i32, edge_scale_y: f64
): f64 {
    const center = luminance(input, y * width + x);
    var sum: f64 = 0.0;
    var total: f64 = 0.0;
    var dy = -radius;
    while dy <= radius {
        const source_y = coordinate(y, dy, height);
        var dx = -radius;
        while dx <= radius {
            const source_x = coordinate(x, dx, width);
            const value = luminance(input, source_y * width + source_x);
            const delta = (value - center) / edge_scale_y;
            const distance = (dx * dx + dy * dy) as f64;
            const weight = 1.0 / ((1.0 + distance) * (1.0 + delta * delta));
            sum = sum + weight * value;
            total = total + weight;
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    return sum / total;
}

fn offset(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, asset: ClarityAsset
): f64 {
    if asset.amount == 0.0 or asset.maximum_offset_y == 0.0 {
        return 0.0;
    }
    const fine = low_pass(input, width, height, x, y, 1, asset.edge_scale_y);
    const coarse = low_pass(input, width, height, x, y, 3, asset.edge_scale_y);
    const band = fine - coarse;
    var threshold = asset.noise_threshold_y;
    if threshold < 0.000000000001 {
        threshold = 0.000000000001;
    }
    if band >= -threshold and band <= threshold {
        return 0.0;
    }
    var change = asset.amount * band;
    if change > asset.maximum_offset_y {
        change = asset.maximum_offset_y;
    }
    if change < -asset.maximum_offset_y {
        change = -asset.maximum_offset_y;
    }
    return change;
}

// Immutable interleaved f32 RGB input and disjoint caller-owned output.
// Clamp-to-edge borders require a three-pixel halo. Status: 0 success,
// 1 invalid asset, 2 shape/limit, 3 nonfinite input, 4 nonfinite result,
// 7 cancelled. Every pass polls each row; a failed output is invalid.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: ClarityAsset, output: []f32,
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
    while pass < 3 {
        var y: usize = 0;
        while y < height {
            if cancelled(context) {
                return 7;
            }
            var x: usize = 0;
            while x < width {
                const index = (y * width + x) * 3;
                if pass == 0 {
                    var channel: usize = 0;
                    while channel < 3 {
                        if not core.finite_sample(input[index + channel]) {
                            return 3;
                        }
                        channel = channel + 1;
                    }
                } else {
                    const change = offset(input, width, height, x, y, asset);
                    var channel: usize = 0;
                    while channel < 3 {
                        var value = input[index + channel];
                        if change != 0.0 {
                            const rounded = math.to_f32_rounded(input[index + channel] as f64 + change);
                            if rounded is result {
                                value = result;
                            } else {
                                return 4;
                            }
                        }
                        if pass == 1 {
                            if not core.finite_sample(value) {
                                return 4;
                            }
                        } else {
                            output[index + channel] = value;
                        }
                        channel = channel + 1;
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
