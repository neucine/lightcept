import .engine.core.core;
import .engine.core.sha256;
import std.math;

// Caller-supplied opponent-chroma map v1. RGB input/output are scene-linear
// D65 reference-white units in [-0.25,8] and [-16,16], respectively. The
// primaries are declared, never inferred from RGB16 storage or a camera ID.
pub const algorithm_version: u32 = 1;
pub const REC2020_D65: u32 = 1;
pub const LINEAR_SRGB_D65: u32 = 2;
pub const maximum_axis: usize = 17;
pub const maximum_pixels: usize = 16777216;

pub struct Delta {
    pub cb: f64;
    pub cr: f64;
}

pub struct ChromaMapAsset {
    pub version: u32;
    pub primaries: u32;
    // Row-major RGB -> (Y,Cb,Cr) and its inverse. Y, Cb, Cr share
    // reference-white units; matrix pairs must invert within 1e-5.
    pub to_opponent: [9]f64;
    pub from_opponent: [9]f64;
    // First axis is Cb/Y, second is Cr/Y. Both are dimensionless.
    pub cb_origin: f64;
    pub cr_origin: f64;
    pub cb_step: f64;
    pub cr_step: f64;
    pub cb_count: usize;
    pub cr_count: usize;
    // Row-major [cb_index * cr_count + cr_index] ratio corrections.
    pub deltas: [:]Delta;
    pub neutral_radius: f64;
    pub strength: f64;
}

fn no_cancel(context: usize): bool {
    return false;
}
fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}
fn finite_bounded(value: f64, limit: f64): bool {
    return value >= -limit and value <= limit;
}

// Status 0 valid, 1 malformed asset, 7 cancelled. Grid spans and table size
// are checked before indexed reads. Cancellation is polled during validation.
pub fn validate(asset: &const ChromaMapAsset,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if asset.version != algorithm_version
    or (asset.primaries != REC2020_D65 and asset.primaries != LINEAR_SRGB_D65)
    or asset.cb_count < 2 or asset.cb_count > maximum_axis
    or asset.cr_count < 2 or asset.cr_count > maximum_axis
    or asset.deltas.len() != asset.cb_count * asset.cr_count
    or not finite_bounded(asset.cb_origin, 4.0)
    or not finite_bounded(asset.cr_origin, 4.0)
    or not (asset.cb_step >= 0.0001 and asset.cb_step <= 4.0)
    or not (asset.cr_step >= 0.0001 and asset.cr_step <= 4.0)
    or not finite_bounded(asset.cb_origin + asset.cb_step * ((asset.cb_count - 1) as f64), 4.0)
    or not finite_bounded(asset.cr_origin + asset.cr_step * ((asset.cr_count - 1) as f64), 4.0)
    or not (asset.neutral_radius >= 0.0001 and asset.neutral_radius <= 2.0)
    or not (asset.strength >= 0.0 and asset.strength <= 1.0) {
        return 1;
    }
    var index: usize = 0;
    while index < 9 {
        if cancelled(context) {
            return 7;
        }
        if not finite_bounded(asset.to_opponent[index], 16.0)
        or not finite_bounded(asset.from_opponent[index], 16.0) {
            return 1;
        }
        index = index + 1;
    }
    if not (asset.to_opponent[0] >= 0.0 and asset.to_opponent[1] >= 0.0
        and asset.to_opponent[2] >= 0.0
    )
    or absolute(asset.to_opponent[0] + asset.to_opponent[1]
        + asset.to_opponent[2] - 1.0
    ) > 0.00001
    or absolute(asset.to_opponent[3] + asset.to_opponent[4]
        + asset.to_opponent[5]
    ) > 0.00001
    or absolute(asset.to_opponent[6] + asset.to_opponent[7]
        + asset.to_opponent[8]
    ) > 0.00001 {
        return 1;
    }
    var row: usize = 0;
    while row < 3 {
        var column: usize = 0;
        while column < 3 {
            var product: f64 = 0.0;
            var term: usize = 0;
            while term < 3 {
                product = product + asset.from_opponent[row * 3 + term]
                * asset.to_opponent[term * 3 + column];
                term = term + 1;
            }
            var expected: f64 = 0.0;
            if row == column {
                expected = 1.0;
            }
            if absolute(product - expected) > 0.00001 {
                return 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    index = 0;
    while index < asset.deltas.len() {
        if cancelled(context) {
            return 7;
        }
        if not finite_bounded(asset.deltas[index].cb, 2.0)
        or not finite_bounded(asset.deltas[index].cr, 2.0) {
            return 1;
        }
        index = index + 1;
    }
    return 0;
}

pub fn valid(asset: &const ChromaMapAsset): bool {
    return validate(asset, no_cancel, 0) == 0;
}

fn write_u32(bytes: []u8, offset: usize, value: u32) {
    var index: usize = 0;
    while index < 4 {
        const shift = ((3 - index) * 8) as u32;
        bytes[offset + index] = ((value >> shift) & 255) as u8;
        index = index + 1;
    }
}
fn write_f64(bytes: []u8, offset: usize, value: f64) {
    const bits = value as! u64;
    var index: usize = 0;
    while index < 8 {
        const shift = ((7 - index) * 8) as u32;
        bytes[offset + index] = ((bits >> shift) & 255) as u8;
        index = index + 1;
    }
}

// Canonical SHA-256 asset identity: version, primaries and grid counts as
// big-endian u32, then matrices, grid coordinates, neutral radius, strength,
// and table pairs as big-endian IEEE-754 f64. Status 0, 1 invalid, 7 cancelled.
pub fn digest(asset: &const ChromaMapAsset, output: []u8,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const status = validate(asset, cancelled, context);
    if status != 0 {
        return status;
    }
    if output.len() != 32 {
        return 1;
    }
    var bytes: [5000]u8 = [0] ** 5000;
    write_u32(bytes[0..], 0, asset.version);
    write_u32(bytes[0..], 4, asset.primaries);
    write_u32(bytes[0..], 8, asset.cb_count as u32);
    write_u32(bytes[0..], 12, asset.cr_count as u32);
    var offset: usize = 16;
    var index: usize = 0;
    while index < 9 {
        if cancelled(context) {
            return 7;
        }
        write_f64(bytes[0..], offset, asset.to_opponent[index]);
        offset = offset + 8;
        index = index + 1;
    }
    index = 0;
    while index < 9 {
        if cancelled(context) {
            return 7;
        }
        write_f64(bytes[0..], offset, asset.from_opponent[index]);
        offset = offset + 8;
        index = index + 1;
    }
    const fields: [6]f64 = [asset.cb_origin, asset.cr_origin, asset.cb_step,
        asset.cr_step, asset.neutral_radius, asset.strength
    ];
    index = 0;
    while index < 6 {
        write_f64(bytes[0..], offset, fields[index]);
        offset = offset + 8;
        index = index + 1;
    }
    index = 0;
    while index < asset.deltas.len() {
        if cancelled(context) {
            return 7;
        }
        write_f64(bytes[0..], offset, asset.deltas[index].cb);
        write_f64(bytes[0..], offset + 8, asset.deltas[index].cr);
        offset = offset + 16;
        index = index + 1;
    }
    return sha256.digest(bytes[0..offset], output, cancelled, context);
}

fn clamped_grid(value: f64, origin: f64, step: f64, count: usize): f64 {
    const index = (value - origin) / step;
    if index <= 0.0 {
        return 0.0;
    }
    const last = (count - 1) as f64;
    if index >= last {
        return last;
    }
    return index;
}

fn lookup(asset: &const ChromaMapAsset, cb_ratio: f64, cr_ratio: f64): Delta {
    const cb_position = clamped_grid(cb_ratio, asset.cb_origin, asset.cb_step, asset.cb_count);
    const cr_position = clamped_grid(cr_ratio, asset.cr_origin, asset.cr_step, asset.cr_count);
    var cb_low = cb_position as usize;
    var cr_low = cr_position as usize;
    if cb_low >= asset.cb_count - 1 {
        cb_low = asset.cb_count - 2;
    }
    if cr_low >= asset.cr_count - 1 {
        cr_low = asset.cr_count - 2;
    }
    const cb_fraction = cb_position - (cb_low as f64);
    const cr_fraction = cr_position - (cr_low as f64);
    const a = asset.deltas[cb_low * asset.cr_count + cr_low];
    const b = asset.deltas[(cb_low + 1) * asset.cr_count + cr_low];
    const c = asset.deltas[cb_low * asset.cr_count + cr_low + 1];
    const d = asset.deltas[(cb_low + 1) * asset.cr_count + cr_low + 1];
    const low_cb = a.cb + cb_fraction * (b.cb - a.cb);
    const high_cb = c.cb + cb_fraction * (d.cb - c.cb);
    const low_cr = a.cr + cb_fraction * (b.cr - a.cr);
    const high_cr = c.cr + cb_fraction * (d.cr - c.cr);
    return {
        cb: low_cb + cr_fraction * (high_cb - low_cb),
        cr: low_cr + cr_fraction * (high_cr - low_cr)
    };
}

fn mapped(asset: &const ChromaMapAsset, red: f64, green: f64, blue: f64): [3]f64 {
    if asset.strength == 0.0 {
        return [red, green, blue];
    }
    const matrix = asset.to_opponent;
    const y = matrix[0] * red + matrix[1] * green + matrix[2] * blue;
    if y <= 0.0 {
        return [red, green, blue];
    }
    const cb = matrix[3] * red + matrix[4] * green + matrix[5] * blue;
    const cr = matrix[6] * red + matrix[7] * green + matrix[8] * blue;
    if cb == 0.0 and cr == 0.0 {
        return [red, green, blue];
    }
    const cb_ratio = cb / y;
    const cr_ratio = cr / y;
    const delta = lookup(asset, cb_ratio, cr_ratio);
    var spread = absolute(cb_ratio);
    if absolute(cr_ratio) > spread {
        spread = absolute(cr_ratio);
    }
    var weight = spread / asset.neutral_radius;
    if weight > 1.0 {
        weight = 1.0;
    }
    const mapped_cb = cb + y * asset.strength * weight * delta.cb;
    const mapped_cr = cr + y * asset.strength * weight * delta.cr;
    const inverse = asset.from_opponent;
    return [inverse[0] * y + inverse[1] * mapped_cb + inverse[2] * mapped_cr,
        inverse[3] * y + inverse[4] * mapped_cb + inverse[5] * mapped_cr,
        inverse[6] * y + inverse[7] * mapped_cb + inverse[8] * mapped_cr
    ];
}

// Immutable interleaved f32 scene RGB and disjoint caller-owned f32 output.
// Bilinear ratio-grid lookup clamps outside the grid. Y<=0 passes through;
// zero chroma gets zero correction. Status 0 success, 1 asset, 2 shape/limit,
// 3 input, 4 output, 7 cancellation. Both passes poll each row; all samples
// and projected outputs are checked before the first write. Failure invalidates
// output for publication. There is no spatial halo or source mutation.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: &const ChromaMapAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const asset_status = validate(asset, cancelled, context);
    if asset_status == 7 {
        return 7;
    }
    if asset_status != 0 {
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
                    if not core.finite_sample(sample) or sample < -0.25 or sample > 8.0 {
                        return 3;
                    }
                    channel = channel + 1;
                }
                const result = mapped(asset, input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64
                );
                channel = 0;
                while channel < 3 {
                    if not finite_bounded(result[channel], 16.0) {
                        return 4;
                    }
                    const rounded = math.to_f32_rounded(result[channel]);
                    if rounded is value {
                        if pass == 1 {
                            output[offset + channel] = value;
                        }
                    } else {
                        return 4;
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
