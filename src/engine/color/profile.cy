import .engine.core.core;
import .engine.core.sha256;
import .engine.color.color_matrix;
import std.math;

// Camera profile v1: immutable camera-linear RGB to scene-linear
// Rec.2020/D65 RGB through camera-to-XYZ D50 matrix and residual 3D LUT.
// The caller pins the expected SHA-256 in its replay plan. The digest covers
// every byte of the matrix, LUT, version and named profile ID.
pub const algorithm_version: u32 = 1;
pub const asset_bytes: usize = 1584;
pub const grid_steps: usize = 5;
pub const maximum_pixels: usize = 16777216;

pub struct ProfileAsset {
    pub bytes: []const u8;
    pub expected_sha256: [32]u8;
}

fn u32le(bytes: []const u8, offset: usize): u32 {
    return (bytes[offset] as u32)
    | ((bytes[offset + 1] as u32) << 8)
    | ((bytes[offset + 2] as u32) << 16)
    | ((bytes[offset + 3] as u32) << 24);
}

fn u64le(bytes: []const u8, offset: usize): u64 {
    var value: u64 = 0;
    var index: usize = 0;
    while index < 8 {
        value = value | ((bytes[offset + index] as u64) << ((index * 8) as u32));
        index = index + 1;
    }
    return value;
}

fn matrix_value(bytes: []const u8, index: usize): f64 {
    return u64le(bytes, 12 + index * 8) as! f64;
}

fn residual_value(bytes: []const u8, node: usize, channel: usize): f64 {
    const bits = u32le(bytes, 84 + (node * 3 + channel) * 4);
    const value = bits as! f32;
    return value as f64;
}

// Exact fixed file layout: bytes 0..3 'LCP1'; 4..7 version=1 little-endian;
// 8..11 nonzero profile ID; 12..83 nine row-major f64 camera-to-XYZ D50
// coefficients; 84..1583 5x5x5 RGB-major f32 scene RGB residual triples.
// All numeric payload values use little-endian IEEE-754. Status 0 valid,
// 1 format/range, 2 SHA-256 mismatch, 7 cancelled. No untrusted pointer use.
pub fn validate(asset: &const ProfileAsset,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if asset.bytes.len() != asset_bytes
    or asset.bytes[0] != 76 or asset.bytes[1] != 67
    or asset.bytes[2] != 80 or asset.bytes[3] != 49
    or u32le(asset.bytes, 4) != algorithm_version
    or u32le(asset.bytes, 8) == 0 {
        return 1;
    }
    var nonzero = false;
    var index: usize = 0;
    while index < 32 {
        if asset.expected_sha256[index] != 0 {
            nonzero = true;
        }
        index = index + 1;
    }
    if not nonzero {
        return 1;
    }
    var actual: [32]u8 = [0] ** 32;
    const hash_status = sha256.digest(asset.bytes, actual[0..], cancelled, context);
    if hash_status == 7 {
        return 7;
    }
    index = 0;
    while index < 32 {
        if actual[index] != asset.expected_sha256[index] {
            return 2;
        }
        index = index + 1;
    }
    index = 0;
    while index < 9 {
        const value = matrix_value(asset.bytes, index);
        if not (value >= -8.0 and value <= 8.0) {
            return 1;
        }
        index = index + 1;
    }
    index = 0;
    while index < 125 {
        var channel: usize = 0;
        while channel < 3 {
            const value = residual_value(asset.bytes, index, channel);
            if not (value >= -0.25 and value <= 0.25) {
                return 1;
            }
            channel = channel + 1;
        }
        index = index + 1;
    }
    return 0;
}

fn clamp01(value: f64): f64 {
    if value < 0.0 {
        return 0.0;
    }
    if value > 1.0 {
        return 1.0;
    }
    return value;
}

fn grid_coordinate(value: f64): [2]f64 {
    const position = clamp01(value) * 4.0;
    if position >= 4.0 {
        return [3.0, 1.0];
    }
    const lower = position as usize;
    return [lower as f64, position - lower as f64];
}

// Trilinear residual interpolation. Camera values outside [0,1] use the
// nearest LUT boundary, while matrix conversion retains signed/headroom data.
fn residual(asset: &const ProfileAsset, red: f64, green: f64,
    blue: f64, channel: usize
): f64 {
    const r = grid_coordinate(red);
    const g = grid_coordinate(green);
    const b = grid_coordinate(blue);
    const r0 = r[0] as usize;
    const g0 = g[0] as usize;
    const b0 = b[0] as usize;
    var total: f64 = 0.0;
    var ir: usize = 0;
    while ir < 2 {
        var ig: usize = 0;
        while ig < 2 {
            var ib: usize = 0;
            while ib < 2 {
                var weight = 1.0 - r[1];
                if ir == 1 {
                    weight = r[1];
                }
                if ig == 0 {
                    weight = weight * (1.0 - g[1]);
                } else {
                    weight = weight * g[1];
                }
                if ib == 0 {
                    weight = weight * (1.0 - b[1]);
                } else {
                    weight = weight * b[1];
                }
                const node = ((r0 + ir) * grid_steps + g0 + ig) * grid_steps + b0 + ib;
                total = total + weight * residual_value(asset.bytes, node, channel);
                ib = ib + 1;
            }
            ig = ig + 1;
        }
        ir = ir + 1;
    }
    return total;
}

// Immutable interleaved camera-linear f32 RGB in [-0.25,8], disjoint
// same-size scene-linear Rec.2020/D65 output in [-128,128]. One named,
// hash-pinned asset controls the matrix and bounded residual LUT. Status:
// 0 success, 1 asset, 2 hash, 3 shape/limit, 4 input, 5 result, 7 cancelled.
// Validate projected output in a first pass before writes; poll each row in
// both passes. Any nonzero status invalidates the complete output.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: &const ProfileAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const asset_status = validate(asset, cancelled, context);
    if asset_status != 0 {
        return asset_status;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 3;
    }
    const count = width * height * 3;
    if input.len() != count or output.len() != count {
        return 3;
    }
    var matrix: [9]f64 = [0.0] ** 9;
    var index: usize = 0;
    while index < 9 {
        matrix[index] = matrix_value(asset.bytes, index);
        index = index + 1;
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
                var channel: usize = 0;
                while channel < 3 {
                    const sample = input[offset + channel];
                    if not core.finite_sample(sample) or sample < -0.25
                    or sample > 8.0 {
                        return 4;
                    }
                    channel = channel + 1;
                }
                const red = input[offset] as f64;
                const green = input[offset + 1] as f64;
                const blue = input[offset + 2] as f64;
                const converted = color_matrix.camera_to_working(matrix, red, green, blue);
                const base: [3]f64 = [converted.red, converted.green, converted.blue];
                channel = 0;
                while channel < 3 {
                    const value = base[channel] + residual(asset, red, green, blue, channel);
                    if not (value >= -128.0 and value <= 128.0) {
                        return 5;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(value);
                        if rounded is sample {
                            output[offset + channel] = sample;
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
