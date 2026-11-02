import .engine.core.core;
import std.math;

// Diagnostic capture sharpening v1. Scene-linear Rec.2020/D65 RGB in/out.
// Gaussian luminance blur at radius 1 or 2 is subtracted from input luminance.
// A threshold suppresses small detail; a bounded equal-channel offset adds
// high-frequency contrast while preserving absolute RGB differences.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct SharpenAsset {
    pub version: u32;
    pub radius_pixels: u32;
    pub amount: f64;
    pub threshold_y: f64;
    pub maximum_offset_y: f64;
}

pub fn valid(asset: SharpenAsset): bool {
    return asset.version == algorithm_version
    and asset.radius_pixels >= 1 and asset.radius_pixels <= 2
    and asset.amount >= 0.0 and asset.amount <= 2.0
    and asset.threshold_y >= 0.0 and asset.threshold_y <= 0.1
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
    if magnitude >= limit {
        return limit - 1;
    }
    if position >= limit - magnitude {
        return limit - 1;
    }
    return position + magnitude;
}

fn weight(radius: u32, displacement: i32): f64 {
    var distance = displacement;
    if distance < 0 {
        distance = -distance;
    }
    if radius == 1 {
        if distance == 0 {
            return 2.0;
        }
        return 1.0;
    }
    if distance == 0 {
        return 6.0;
    }
    if distance == 1 {
        return 4.0;
    }
    return 1.0;
}

fn luminance(input: []const f32, pixel: usize): f64 {
    const index = pixel * 3;
    return 0.2627 * (input[index] as f64)
    + 0.6780 * (input[index + 1] as f64)
    + 0.0593 * (input[index + 2] as f64);
}

fn offset(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, asset: SharpenAsset
): f64 {
    if asset.amount == 0.0 or asset.maximum_offset_y == 0.0 {
        return 0.0;
    }
    const radius = asset.radius_pixels as i32;
    var blurred: f64 = 0.0;
    var dy: i32 = -radius;
    while dy <= radius {
        const source_y = coordinate(y, dy, height);
        var dx: i32 = -radius;
        while dx <= radius {
            const source_x = coordinate(x, dx, width);
            blurred = blurred + weight(asset.radius_pixels, dy)
            * weight(asset.radius_pixels, dx)
            * luminance(input, source_y * width + source_x);
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    if asset.radius_pixels == 1 {
        blurred = blurred / 16.0;
    } else {
        blurred = blurred / 256.0;
    }
    const detail = luminance(input, y * width + x) - blurred;
    if detail >= -asset.threshold_y and detail <= asset.threshold_y {
        return 0.0;
    }
    var result = asset.amount * detail;
    if result > asset.maximum_offset_y {
        result = asset.maximum_offset_y;
    }
    if result < -asset.maximum_offset_y {
        result = -asset.maximum_offset_y;
    }
    return result;
}

// Immutable interleaved f32 RGB input and disjoint caller-owned output.
// Image extent is bounded to maximum_pixels; border samples replicate the
// nearest edge pixel. Status: 0 success, 1 asset, 2 shape/limit, 3 nonfinite
// input, 4 nonfinite f32 result, 7 cancelled. Validate all output samples
// before writing; poll every row in both passes. Nonzero status invalidates
// output, including any partial result after cancellation.
pub fn apply(input: []const f32, width: usize, height: usize, asset: SharpenAsset,
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
            const change = offset(input, width, height, column, row, asset);
            var channel: usize = 0;
            while channel < 3 {
                if change != 0.0 {
                    const rounded = math.to_f32_rounded(input[index + channel] as f64 + change);
                    if rounded is value {
                        if not core.finite_sample(value) {
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
            const change = offset(input, width, height, column, row, asset);
            var channel: usize = 0;
            while channel < 3 {
                if change == 0.0 {
                    output[index + channel] = input[index + channel];
                } else {
                    const rounded = math.to_f32_rounded(input[index + channel] as f64 + change);
                    if rounded is value {
                        output[index + channel] = value;
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
