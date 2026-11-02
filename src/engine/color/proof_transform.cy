import .engine.core.core;
import .engine.core.sha256;
import std.math;

// Soft proof v1 applies a precomputed, hash-pinned 5x5x5 display RGB LUT.
// An external colour management process must build the LUT from a measured
// destination ICC profile for the declared intent. This kernel does not
// interpret arbitrary ICC tags or infer a transform from a profile header.
pub const algorithm_version: u32 = 1;
pub const asset_bytes: usize = 1548;
pub const maximum_pixels: usize = 16777216;
pub const intent_relative_colorimetric: u32 = 1;
pub const intent_absolute_colorimetric: u32 = 2;

pub struct ProofAsset {
    pub bytes: []const u8;
    pub expected_sha256: [32]u8;
    pub destination_icc: []const u8;
}

pub struct ProofReport {
    // 0 success, 1 asset, 2 digest mismatch, 3 shape, 4 input,
    // 5 LUT output, 7 cancelled. Nonzero invalidates output and identity.
    pub status: u32;
    pub version: u32;
    pub destination_id: u32;
    pub intent: u32;
    pub comparison_id: u32;
    pub pixels: usize;
}

fn failure(status: u32): ProofReport {
    return {
        status: status,
        version: algorithm_version,
        destination_id: 0,
        intent: 0,
        comparison_id: 0,
        pixels: 0
    };
}

fn u32le(bytes: []const u8, offset: usize): u32 {
    return (bytes[offset] as u32) | ((bytes[offset + 1] as u32) << 8)
    | ((bytes[offset + 2] as u32) << 16)
    | ((bytes[offset + 3] as u32) << 24);
}

fn node_value(bytes: []const u8, node: usize, channel: usize): f64 {
    const bits = u32le(bytes, 48 + (node * 3 + channel) * 4);
    return (bits as! f32) as f64;
}

fn same_digest(actual: [32]u8, expected: []const u8): bool {
    var i: usize = 0;
    while i < 32 {
        if actual[i] != expected[i] {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fn icc_header_valid(bytes: []const u8): bool {
    if bytes.len() < 128 or bytes.len() > 16777216 {
        return false;
    }
    const declared = (bytes[0] as usize) * 16777216
    + (bytes[1] as usize) * 65536 + (bytes[2] as usize) * 256
    + bytes[3] as usize;
    if declared != bytes.len() {
        return false;
    }
    // Output device, RGB data, XYZ PCS and ICC signature.
    return bytes[12] == 112 and bytes[13] == 114
    and bytes[14] == 116 and bytes[15] == 114
    and bytes[16] == 82 and bytes[17] == 71
    and bytes[18] == 66 and bytes[19] == 32
    and bytes[20] == 88 and bytes[21] == 89
    and bytes[22] == 90 and bytes[23] == 32
    and bytes[36] == 97 and bytes[37] == 99
    and bytes[38] == 115 and bytes[39] == 112;
}

// LSP1 header: magic, version, nonzero destination ID, intent (1 relative
// or 2 absolute colorimetric), destination ICC SHA-256, then 125 RGB-major
// little-endian f32 output triples. Both asset and ICC bytes are immutable.
pub fn validate(asset: &const ProofAsset,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const b = asset.bytes;
    if b.len() != asset_bytes or b[0] != 76 or b[1] != 83
    or b[2] != 80 or b[3] != 49
    or u32le(b, 4) != algorithm_version or u32le(b, 8) == 0
    or (u32le(b, 12) != intent_relative_colorimetric
        and u32le(b, 12) != intent_absolute_colorimetric
    )
    or not icc_header_valid(asset.destination_icc) {
        return 1;
    }
    var asset_digest: [32]u8 = [0] ** 32;
    if sha256.digest(b, asset_digest[0..], cancelled, context) == 7 {
        return 7;
    }
    if not same_digest(asset_digest, asset.expected_sha256[0..]) {
        return 2;
    }
    var icc_digest: [32]u8 = [0] ** 32;
    if sha256.digest(asset.destination_icc, icc_digest[0..], cancelled, context) == 7 {
        return 7;
    }
    if not same_digest(icc_digest, b[16..48]) {
        return 2;
    }
    var node: usize = 0;
    while node < 125 {
        if cancelled(context) {
            return 7;
        }
        var channel: usize = 0;
        while channel < 3 {
            const value = node_value(b, node, channel);
            if not (value >= 0.0 and value <= 1.0) {
                return 1;
            }
            channel = channel + 1;
        }
        node = node + 1;
    }
    return 0;
}

fn coordinate(sample: f64): [2]f64 {
    const position = sample * 4.0;
    if position >= 4.0 {
        return [3.0, 1.0];
    }
    const lower = position as usize;
    return [lower as f64, position - lower as f64];
}

fn interpolate(bytes: []const u8, red: f64, green: f64,
    blue: f64, channel: usize
): f64 {
    const r = coordinate(red);
    const g = coordinate(green);
    const b = coordinate(blue);
    const r0 = r[0] as usize;
    const g0 = g[0] as usize;
    const b0 = b[0] as usize;
    var sum: f64 = 0.0;
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
                const node = ((r0 + ir) * 5 + g0 + ig) * 5 + b0 + ib;
                sum = sum + weight * node_value(bytes, node, channel);
                ib = ib + 1;
            }
            ig = ig + 1;
        }
        ir = ir + 1;
    }
    return sum;
}

// Immutable encoded sRGB f32 [0,1] to disjoint encoded sRGB f32 [0,1],
// top-left RGB row-major. comparison_id names the unproofed view snapshot;
// the successful tuple (comparison_id,destination_id,intent,asset SHA-256)
// identifies the soft-proof comparison. Poll before every row in two passes.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: &const ProofAsset, comparison_id: u32, output: []f32,
    cancelled: fn (usize): bool, context: usize
): ProofReport {
    const asset_status = validate(asset, cancelled, context);
    if asset_status != 0 {
        return failure(asset_status);
    }
    if comparison_id == 0 {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(3);
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return failure(3);
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return failure(7);
            }
            var column: usize = 0;
            while column < width {
                const offset = (row * width + column) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    const sample = input[offset + channel];
                    if not core.finite_sample(sample) or sample < 0.0 or sample > 1.0 {
                        return failure(4);
                    }
                    channel = channel + 1;
                }
                channel = 0;
                while channel < 3 {
                    const value = interpolate(asset.bytes, input[offset] as f64,
                        input[offset + 1] as f64, input[offset + 2] as f64, channel
                    );
                    if not (value >= 0.0 and value <= 1.0) {
                        return failure(5);
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(value);
                        if rounded is sample {
                            output[offset + channel] = sample;
                        } else {
                            return failure(5);
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
    return {
        status: 0,
        version: algorithm_version,
        destination_id: u32le(asset.bytes, 8),
        intent: u32le(asset.bytes, 12),
        comparison_id: comparison_id,
        pixels: pixels
    };
}
