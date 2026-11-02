import .engine.color.proof_transform;
import .engine.core.sha256;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn digest(bytes: []const u8): [32]u8 {
    var result: [32]u8 = [0] ** 32;
    assert(sha256.digest(bytes, result[0..], no_cancel, 0) == 0);
    return result;
}

fn destination_icc(): [128]u8 {
    var bytes: [128]u8 = [0] ** 128;
    bytes[3] = 128;
    bytes[12] = 112;
    bytes[13] = 114;
    bytes[14] = 116;
    bytes[15] = 114;
    bytes[16] = 82;
    bytes[17] = 71;
    bytes[18] = 66;
    bytes[19] = 32;
    bytes[20] = 88;
    bytes[21] = 89;
    bytes[22] = 90;
    bytes[23] = 32;
    bytes[36] = 97;
    bytes[37] = 99;
    bytes[38] = 115;
    bytes[39] = 112;
    return bytes;
}

fn write_u32(bytes: []u8, offset: usize, value: u32) {
    bytes[offset] = (value & 255) as u8;
    bytes[offset + 1] = ((value >> 8) & 255) as u8;
    bytes[offset + 2] = ((value >> 16) & 255) as u8;
    bytes[offset + 3] = ((value >> 24) & 255) as u8;
}

fn identity_asset(icc_hash: [32]u8): [1548]u8 {
    var bytes: [1548]u8 = [0] ** 1548;
    bytes[0] = 76;
    bytes[1] = 83;
    bytes[2] = 80;
    bytes[3] = 49;
    bytes[4] = 1;
    bytes[8] = 9;
    bytes[12] = 1;
    var i: usize = 0;
    while i < 32 {
        bytes[16 + i] = icc_hash[i];
        i = i + 1;
    }
    const values: [5]u32 = [0, 0x3e800000, 0x3f000000, 0x3f400000, 0x3f800000];
    var r: usize = 0;
    while r < 5 {
        var g: usize = 0;
        while g < 5 {
            var b: usize = 0;
            while b < 5 {
                const offset = 48 + ((r * 5 + g) * 5 + b) * 12;
                write_u32(bytes[0..], offset, values[r]);
                write_u32(bytes[0..], offset + 4, values[g]);
                write_u32(bytes[0..], offset + 8, values[b]);
                b = b + 1;
            }
            g = g + 1;
        }
        r = r + 1;
    }
    return bytes;
}

test "proof LUT trilinear interpolation and comparison identity" {
    const icc = destination_icc();
    const bytes = identity_asset(digest(icc[0..]));
    const asset: proof_transform.ProofAsset = {
        bytes: bytes[0..],
        expected_sha256: digest(bytes[0..]),
        destination_icc: icc[0..]
    };
    const input: [9]f32 = [0.125, 0.375, 0.625, 1.0, 0.0, 0.5,
        0.0, 0.75, 1.0
    ];
    var output: [9]f32 = [9.0] ** 9;
    const report = proof_transform.apply(input[0..], 3, 1, &asset,
        42, output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.destination_id == 9
        and report.intent == 1 and report.comparison_id == 42
        and report.pixels == 3
    );
    var i: usize = 0;
    while i < 9 {
        assert(output[i] == input[i]);
        i = i + 1;
    }
}

test "proof LUT changes a photographic color strip under absolute intent" {
    const icc = destination_icc();
    var bytes = identity_asset(digest(icc[0..]));
    bytes[12] = 2;
    const red_values: [5]u32 = [0, 0x3e000000, 0x3e800000,
        0x3ec00000, 0x3f000000
    ];
    var r: usize = 0;
    while r < 5 {
        var g: usize = 0;
        while g < 5 {
            var b: usize = 0;
            while b < 5 {
                const offset = 48 + ((r * 5 + g) * 5 + b) * 12;
                write_u32(bytes[0..], offset, red_values[r]);
                b = b + 1;
            }
            g = g + 1;
        }
        r = r + 1;
    }
    const asset: proof_transform.ProofAsset = {
        bytes: bytes[0..],
        expected_sha256: digest(bytes[0..]),
        destination_icc: icc[0..]
    };
    const input: [12]f32 = [0.125, 0.125, 0.125,
        0.75, 0.25, 0.125,
        0.25, 0.5, 0.75,
        1.0, 1.0, 1.0
    ];
    var output: [12]f32 = [9.0] ** 12;
    const report = proof_transform.apply(input[0..], 2, 2, &asset,
        43, output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.intent == 2
        and report.comparison_id == 43 and report.destination_id == 9
    );
    assert(output[0] == 0.0625 and output[1] == 0.125);
    assert(output[3] == 0.375 and output[4] == 0.25);
    assert(output[6] == 0.125 and output[8] == 0.75);
    assert(output[9] == 0.5 and output[10] == 1.0);
}

test "proof asset and destination bytes are both authenticated" {
    const icc = destination_icc();
    const bytes = identity_asset(digest(icc[0..]));
    const hash = digest(bytes[0..]);
    const asset: proof_transform.ProofAsset = {
        bytes: bytes[0..],
        expected_sha256: hash,
        destination_icc: icc[0..]
    };
    assert(proof_transform.validate(&asset, no_cancel, 0) == 0);
    var altered_icc = icc;
    altered_icc[100] = 12;
    const altered_profile: proof_transform.ProofAsset = {
        bytes: bytes[0..],
        expected_sha256: hash,
        destination_icc: altered_icc[0..]
    };
    assert(proof_transform.validate(&altered_profile, no_cancel, 0) == 2);
    var altered_bytes = bytes;
    altered_bytes[48] = 1;
    const altered_lut: proof_transform.ProofAsset = {
        bytes: altered_bytes[0..],
        expected_sha256: hash,
        destination_icc: icc[0..]
    };
    assert(proof_transform.validate(&altered_lut, no_cancel, 0) == 2);
    assert(proof_transform.validate(&asset, cancel, 0) == 7);
}

test "proof validates shape samples and cancellation before output" {
    const icc = destination_icc();
    const bytes = identity_asset(digest(icc[0..]));
    const asset: proof_transform.ProofAsset = {
        bytes: bytes[0..],
        expected_sha256: digest(bytes[0..]),
        destination_icc: icc[0..]
    };
    const input: [3]f32 = [0.25, 0.5, 0.75];
    var output: [3]f32 = [9.0] ** 3;
    assert(proof_transform.apply(input[0..], 0, 1, &asset,
        42, output[0..], no_cancel, 0
    ).status == 3);
    const invalid: [3]f32 = [1.25, 0.5, 0.75];
    assert(proof_transform.apply(invalid[0..], 1, 1, &asset,
        42, output[0..], no_cancel, 0
    ).status == 4);
    assert(proof_transform.apply(input[0..], 1, 1, &asset,
        0, output[0..], no_cancel, 0
    ).status == 1);
    assert(proof_transform.apply(input[0..], 1, 1, &asset,
        42, output[0..], cancel, 0
    ).status == 7);
    assert(output[0] == 9.0);
}
