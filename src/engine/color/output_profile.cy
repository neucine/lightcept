// Output ICC profile identity decision v1 for encoded sRGB RGB samples.
// Input bytes are immutable. SHA-256 pins the exact sRGB2014 asset rather
// than trusting the mutable ICC profile ID. No output bytes are written.
import .engine.core.sha256;
pub const algorithm_version: u32 = 1;
pub const srgb2014_bytes: usize = 3024;

pub struct ProfileDecision {
    // 0 accepted, 1 invalid ICC header, 2 identity mismatch, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub byte_count: usize;
}

fn read_be32(bytes: []const u8, offset: usize): usize {
    return (bytes[offset] as usize) * 16777216
    + (bytes[offset + 1] as usize) * 65536
    + (bytes[offset + 2] as usize) * 256
    + bytes[offset + 3] as usize;
}

fn header_valid(bytes: []const u8): bool {
    if bytes.len() != srgb2014_bytes or read_be32(bytes, 0) != bytes.len() {
        return false;
    }
    // ICC profile header: 'mntr' display class, 'RGB ', 'XYZ ', 'acsp'.
    return bytes[12] == 109 and bytes[13] == 110 and bytes[14] == 116 and bytes[15] == 114
    and bytes[16] == 82 and bytes[17] == 71 and bytes[18] == 66 and bytes[19] == 32
    and bytes[20] == 88 and bytes[21] == 89 and bytes[22] == 90 and bytes[23] == 32
    and bytes[36] == 97 and bytes[37] == 99 and bytes[38] == 115 and bytes[39] == 112;
}

// Candidate is an ICC byte slice. The fixed SHA-256 is
// 384b832de3412066743b52a75ee906b6fb9fb8d9e09e936fc2c43223815c6e0a.
// No result is valid on failure or cancellation.
pub fn select(candidate: []const u8,
    cancelled: fn (usize): bool, context: usize
): ProfileDecision {
    if not header_valid(candidate) {
        return {
            status: 1,
            version: algorithm_version,
            byte_count: 0
        };
    }
    var digest: [32]u8 = [0] ** 32;
    const hash_status = sha256.digest(candidate, digest[0..], cancelled, context);
    if hash_status == 7 {
        return {
            status: 7,
            version: algorithm_version,
            byte_count: 0
        };
    }
    const expected: [32]u8 = [
        0x38, 0x4b, 0x83, 0x2d, 0xe3, 0x41, 0x20, 0x66,
        0x74, 0x3b, 0x52, 0xa7, 0x5e, 0xe9, 0x06, 0xb6,
        0xfb, 0x9f, 0xb8, 0xd9, 0xe0, 0x9e, 0x93, 0x6f,
        0xc2, 0xc4, 0x32, 0x23, 0x81, 0x5c, 0x6e, 0x0a
    ];
    var index: usize = 0;
    while index < 32 {
        if digest[index] != expected[index] {
            return {
                status: 2,
                version: algorithm_version,
                byte_count: 0
            };
        }
        index = index + 1;
    }
    return {
        status: 0,
        version: algorithm_version,
        byte_count: srgb2014_bytes
    };
}
