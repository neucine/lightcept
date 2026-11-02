import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 luminance range mask v1. Coverage is unitless
// [0,1], sampled from four increasing luminance knots. Source pixels are read
// only; this stage does not apply an edit or composite another mask.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct RangeAsset {
    pub version: u32;
    pub outer_low: f64;
    pub inner_low: f64;
    pub inner_high: f64;
    pub outer_high: f64;
}

pub fn valid(asset: RangeAsset): bool {
    return asset.version == algorithm_version
    and asset.outer_low >= -1.0 and asset.outer_high <= 8.0
    and asset.outer_low < asset.inner_low
    and asset.inner_low <= asset.inner_high
    and asset.inner_high < asset.outer_high;
}

fn smoothstep(position: f64): f64 {
    return position * position * (3.0 - 2.0 * position);
}

pub fn coverage(asset: RangeAsset, luminance: f64): f64 {
    if luminance <= asset.outer_low or luminance >= asset.outer_high {
        return 0.0;
    }
    if luminance < asset.inner_low {
        return smoothstep((luminance - asset.outer_low) / (asset.inner_low - asset.outer_low));
    }
    if luminance <= asset.inner_high {
        return 1.0;
    }
    return smoothstep((asset.outer_high - luminance) / (asset.outer_high - asset.inner_high));
}

// Interleaved f32 scene-linear RGB input and one f32 coverage per pixel.
// Status: 0 success, 1 asset, 2 shape/limit, 3 source sample,
// 4 unrepresentable rounded coverage, 7 cancelled.
// Asset, extent, and every sample are checked before writes. Poll before work
// and at each row. A nonzero status invalidates output, including a cancelled
// partial buffer. Input and output are disjoint caller-owned buffers.
pub fn build(input: []const f32, width: usize, height: usize, asset: RangeAsset,
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
    if input.len() != pixels * 3 or output.len() != pixels {
        return 2;
    }
    var pixel: usize = 0;
    while pixel < pixels {
        if pixel % width == 0 and cancelled(context) {
            return 7;
        }
        const index = pixel * 3;
        if not (core.finite_sample(input[index]) and input[index] >= -0.25
            and input[index] <= 8.0
            and core.finite_sample(input[index + 1]) and input[index + 1] >= -0.25
            and input[index + 1] <= 8.0
            and core.finite_sample(input[index + 2]) and input[index + 2] >= -0.25
            and input[index + 2] <= 8.0
        ) {
            return 3;
        }
        pixel = pixel + 1;
    }
    if cancelled(context) {
        return 7;
    }
    pixel = 0;
    while pixel < pixels {
        if pixel % width == 0 and cancelled(context) {
            return 7;
        }
        const index = pixel * 3;
        const y = 0.2627 * (input[index] as f64)
        + 0.6780 * (input[index + 1] as f64)
        + 0.0593 * (input[index + 2] as f64);
        const rounded = math.to_f32_rounded(coverage(asset, y));
        if rounded is value {
            output[pixel] = value;
        } else {
            return 4;
        }
        pixel = pixel + 1;
    }
    return 0;
}
