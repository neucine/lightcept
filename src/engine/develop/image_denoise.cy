import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 image denoise v1. A 3x3 bilateral-style scalar
// average uses spatial weights [1,2,1] and rational range weights in luminance
// and two opponent chroma differences. The caller supplies a characterized
// noise model and retains its provenance; this kernel does not estimate noise.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct NoiseAsset {
    pub version: u32;
    pub sigma_y: f64;
    pub sigma_chroma: f64;
    pub strength: f64;
    pub maximum_change: f64;
}

pub fn valid(asset: NoiseAsset): bool {
    return asset.version == algorithm_version
    and asset.sigma_y >= 0.001 and asset.sigma_y <= 0.5
    and asset.sigma_chroma >= 0.001 and asset.sigma_chroma <= 0.5
    and asset.strength >= 0.0 and asset.strength <= 1.0
    and asset.maximum_change >= 0.0 and asset.maximum_change <= 0.5;
}

fn coordinate(position: usize, displacement: i32, limit: usize): usize {
    if displacement < 0 {
        if position == 0 {
            return 0;
        }
        return position - 1;
    }
    if displacement > 0 {
        if position + 1 >= limit {
            return limit - 1;
        }
        return position + 1;
    }
    return position;
}

fn spatial_weight(displacement: i32): f64 {
    if displacement == 0 {
        return 2.0;
    }
    return 1.0;
}

fn luminance(red: f64, green: f64, blue: f64): f64 {
    return 0.2627 * red + 0.6780 * green + 0.0593 * blue;
}

fn filtered_channel(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, channel: usize, asset: NoiseAsset
): f64 {
    const center_index = (y * width + x) * 3;
    const center_red = input[center_index] as f64;
    const center_green = input[center_index + 1] as f64;
    const center_blue = input[center_index + 2] as f64;
    const center_y = luminance(center_red, center_green, center_blue);
    const center_rg = center_red - center_green;
    const center_bg = center_blue - center_green;
    const center_value = input[center_index + channel] as f64;
    if asset.strength == 0.0 or asset.maximum_change == 0.0 {
        return center_value;
    }
    var sum: f64 = 0.0;
    var weights: f64 = 0.0;
    var dy: i32 = -1;
    while dy <= 1 {
        const source_y = coordinate(y, dy, height);
        var dx: i32 = -1;
        while dx <= 1 {
            const source_x = coordinate(x, dx, width);
            const index = (source_y * width + source_x) * 3;
            const red = input[index] as f64;
            const green = input[index + 1] as f64;
            const blue = input[index + 2] as f64;
            const luminance_delta = (luminance(red, green, blue) - center_y) / asset.sigma_y;
            const red_green_delta = ((red - green) - center_rg) / asset.sigma_chroma;
            const blue_green_delta = ((blue - green) - center_bg) / asset.sigma_chroma;
            const distance_squared = luminance_delta * luminance_delta
            + red_green_delta * red_green_delta + blue_green_delta * blue_green_delta;
            const weight = spatial_weight(dx) * spatial_weight(dy)
            / (1.0 + distance_squared);
            sum = sum + weight * (input[index + channel] as f64);
            weights = weights + weight;
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    var change = asset.strength * (sum / weights - center_value);
    if change > asset.maximum_change {
        change = asset.maximum_change;
    }
    if change < -asset.maximum_change {
        change = -asset.maximum_change;
    }
    return center_value + change;
}

// Immutable interleaved f32 RGB input and disjoint caller-owned output.
// Border samples replicate the nearest edge pixel. Status 0 succeeds, 1
// rejects asset, 2 shape/limit, 3 nonfinite input, 4 nonfinite f32 output,
// 7 cancelled. Validate all results before writes, polling at each row in
// every pass. Any nonzero status invalidates the output buffer.
pub fn apply(input: []const f32, width: usize, height: usize, asset: NoiseAsset,
    output: []f32, cancelled: fn (usize): bool, context: usize
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
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const index = (row * width + column) * 3;
            var channel: usize = 0;
            while channel < 3 {
                if not core.finite_sample(input[index + channel]) {
                    return 3;
                }
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    row = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const index = (row * width + column) * 3;
            var channel: usize = 0;
            while channel < 3 {
                if asset.strength != 0.0 and asset.maximum_change != 0.0 {
                    const rounded = math.to_f32_rounded(filtered_channel(input, width, height,
                        column, row, channel, asset
                    ));
                    if rounded is result {
                        if not core.finite_sample(result) {
                            return 4;
                        }
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
    row = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const index = (row * width + column) * 3;
            var channel: usize = 0;
            while channel < 3 {
                if asset.strength == 0.0 or asset.maximum_change == 0.0 {
                    output[index + channel] = input[index + channel];
                } else {
                    const rounded = math.to_f32_rounded(filtered_channel(input, width, height,
                        column, row, channel, asset
                    ));
                    if rounded is result {
                        output[index + channel] = result;
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
    return 0;
}
