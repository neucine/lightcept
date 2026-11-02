import .engine.core.core;
import std.math;

// Diagnostic grain v1. Scene-linear Rec.2020/D65 RGB input/output. A declared
// u32 seed and source pixel coordinates select two modular hashes. Their
// difference gives zero-centered triangular monochrome noise in [-1,1].
// Amplitude is in linear reference-white units [0,0.1]. All RGB channels
// receive the same offset, preserving absolute channel differences. No clip.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
const modulus: u64 = 2147483647;

pub struct GrainAsset {
    pub version: u32;
    pub seed: u32;
    pub amplitude: f64;
}

pub fn valid(asset: GrainAsset): bool {
    return asset.version == algorithm_version
    and asset.amplitude >= 0.0 and asset.amplitude <= 0.1;
}

fn hash(seed: u32, x: usize, y: usize, salt: u64): u64 {
    // Inputs are bounded by maximum_pixels, so these products fit u64.
    const base = ((seed as u64) * 83492791 + (x as u64) * 73856093
        + (y as u64) * 19349663 + salt
    ) % modulus;
    return (base * base + 374761393) % modulus;
}

fn hash_second(seed: u32, x: usize, y: usize): u64 {
    const base = ((seed as u64) * 961748941 + (x as u64) * 19349663
        + (y as u64) * 73856093 + 1299709
    ) % modulus;
    return (base * base + 668265263) % modulus;
}

pub fn offset(asset: GrainAsset, x: usize, y: usize): f64 {
    if asset.amplitude == 0.0 {
        return 0.0;
    }
    const first = hash(asset.seed, x, y, 104729);
    const second = hash_second(asset.seed, x, y);
    return asset.amplitude * ((first as f64) - (second as f64)) / (modulus as f64);
}

// Caller-owned disjoint interleaved f32 RGB input/output. Status 0 succeeds,
// 1 rejects asset, 2 rejects shape/limit, 3 rejects nonfinite input, 4 rejects
// nonfinite f32 result, 7 cancelled. Validate the complete image before writes.
// Poll before each row in both passes; a cancelled partial output is invalid.
pub fn apply(input: []const f32, width: usize, height: usize, asset: GrainAsset,
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
            const noise = offset(asset, column, row);
            var channel: usize = 0;
            while channel < 3 {
                const sample = input[index + channel];
                if not core.finite_sample(sample) {
                    return 3;
                }
                if asset.amplitude != 0.0 {
                    const rounded = math.to_f32_rounded(sample as f64 + noise);
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
            const noise = offset(asset, column, row);
            var channel: usize = 0;
            while channel < 3 {
                if asset.amplitude == 0.0 {
                    output[index + channel] = input[index + channel];
                } else {
                    const rounded = math.to_f32_rounded(input[index + channel] as f64 + noise);
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
