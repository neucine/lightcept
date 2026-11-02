import .engine.core.core;
import std.math;

// Sampled white-point adjustment v1 in scene-linear Rec.2020/D65 RGB.
// The named reference patch and target RGB are caller-owned evidence.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct Region {
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
}

pub struct WhitePointAsset {
    pub version: u32;
    pub matrix_hash: u64;
    pub region: Region;
    pub sample: [3]f64;
    pub target: [3]f64;
    pub confidence: f64;
}

pub struct WhitePointSampleResult {
    // 0 success; 1 shape/limit; 2 region/provenance;
    // 3 nonfinite/out-of-domain input; 4 insufficient signal;
    // 5 gain outside supported range; 7 cancelled.
    pub status: u32;
    pub asset: WhitePointAsset;
}

fn empty_asset(): WhitePointAsset {
    return {
        version: algorithm_version,
        matrix_hash: 0,
        region: {
            left: 0,
            top: 0,
            width: 0,
            height: 0
        },
        sample: [0.0, 0.0, 0.0],
        target: [0.0, 0.0, 0.0],
        confidence: 0.0
    };
}

fn failure(status: u32): WhitePointSampleResult {
    return {
        status: status,
        asset: empty_asset()
    };
}

fn shape(input_len: usize, width: usize, height: usize): bool {
    return width > 0 and height > 0 and width <= maximum_pixels
    and height <= maximum_pixels / width
    and input_len == width * height * 3;
}

fn region_valid(region: Region, width: usize, height: usize): bool {
    return region.width > 0 and region.height > 0
    and region.left < width and region.top < height
    and region.width <= width - region.left
    and region.height <= height - region.top;
}

// Immutable interleaved f32 input, signed scene-linear range [-0.25,8].
// The half-open region is in pixel coordinates. Poll each sampled row.
// A successful result pins a nonzero upstream camera-matrix hash.
pub fn sample_patch(input: []const f32, width: usize, height: usize,
    region: Region, matrix_hash: u64, target: [3]f64, confidence: f64,
    cancelled: fn (usize): bool, context: usize
): WhitePointSampleResult {
    if not shape(input.len(), width, height) {
        return failure(1);
    }
    if not region_valid(region, width, height) or matrix_hash == 0
    or not (confidence >= 0.0 and confidence <= 1.0) {
        return failure(2);
    }
    var channel: usize = 0;
    while channel < 3 {
        if not (target[channel] >= 0.01 and target[channel] <= 4.0) {
            return failure(2);
        }
        channel = channel + 1;
    }
    var sums: [3]f64 = [0.0, 0.0, 0.0];
    var row: usize = 0;
    while row < region.height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < region.width {
            const index = ((region.top + row) * width + region.left + column) * 3;
            channel = 0;
            while channel < 3 {
                const value = input[index + channel];
                if not core.finite_sample(value) or value < -0.25 or value > 8.0 {
                    return failure(3);
                }
                sums[channel] = sums[channel] + (value as f64);
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    const count = (region.width * region.height) as f64;
    var sample: [3]f64 = [0.0, 0.0, 0.0];
    channel = 0;
    while channel < 3 {
        sample[channel] = sums[channel] / count;
        if sample[channel] < 0.01 {
            return failure(4);
        }
        channel = channel + 1;
    }
    const asset: WhitePointAsset = {
        version: algorithm_version,
        matrix_hash: matrix_hash,
        region: region,
        sample: sample,
        target: target,
        confidence: confidence
    };
    if not valid(asset) {
        return failure(5);
    }
    return {
        status: 0,
        asset: asset
    };
}

fn luminance(rgb: [3]f64): f64 {
    return 0.2627 * rgb[0] + 0.6780 * rgb[1] + 0.0593 * rgb[2];
}

pub fn valid(asset: WhitePointAsset): bool {
    if asset.version != algorithm_version or asset.matrix_hash == 0
    or asset.region.width == 0 or asset.region.height == 0
    or not (asset.confidence >= 0.0 and asset.confidence <= 1.0) {
        return false;
    }
    var channel: usize = 0;
    while channel < 3 {
        if not (asset.sample[channel] >= 0.01 and asset.sample[channel] <= 8.0)
        or not (asset.target[channel] >= 0.01 and asset.target[channel] <= 4.0) {
            return false;
        }
        channel = channel + 1;
    }
    const scale = luminance(asset.sample) / luminance(asset.target);
    channel = 0;
    while channel < 3 {
        const gain = scale * asset.target[channel] / asset.sample[channel];
        if not (gain >= 0.25 and gain <= 4.0) {
            return false;
        }
        channel = channel + 1;
    }
    return true;
}

// Disjoint immutable input and output have identical extent. A zero-confidence
// asset is exact identity. Otherwise each channel gain is interpolated from
// one toward the patch-to-target gain while preserving sampled luminance at
// full confidence. Status 0 success, 1 asset, 2 shape/limit, 3 bad input,
// 4 bad output, 7 cancelled. Failure invalidates output. Poll each pass row.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: WhitePointAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if not shape(input.len(), width, height) or output.len() != input.len() {
        return 2;
    }
    const scale = luminance(asset.sample) / luminance(asset.target);
    var gains: [3]f64 = [1.0, 1.0, 1.0];
    var channel: usize = 0;
    while channel < 3 {
        const full_gain = scale * asset.target[channel] / asset.sample[channel];
        gains[channel] = 1.0 + asset.confidence * (full_gain - 1.0);
        channel = channel + 1;
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
                channel = 0;
                while channel < 3 {
                    const value = input[offset + channel];
                    if not core.finite_sample(value) or value < -0.25 or value > 8.0 {
                        return 3;
                    }
                    const result = (value as f64) * gains[channel];
                    if not (result >= -32.0 and result <= 32.0) {
                        return 4;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(result);
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
