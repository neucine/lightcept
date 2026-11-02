import .engine.core.sha256;
import std.fs;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "SHA-256 matches FIPS empty and abc vectors" {
    const empty: [0]u8 = [];
    const abc: [3]u8 = [97, 98, 99];
    const empty_expected: [32]u8 = [
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55
    ];
    const abc_expected: [32]u8 = [
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    ];
    var digest: [32]u8 = [0] ** 32;
    assert(sha256.digest(empty[0..], digest[0..], no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 32 {
        assert(digest[index] == empty_expected[index]);
        index = index + 1;
    }
    assert(sha256.digest(abc[0..], digest[0..], no_cancel, 0) == 0);
    index = 0;
    while index < 32 {
        assert(digest[index] == abc_expected[index]);
        index = index + 1;
    }
}

test "SHA-256 matches pinned sRGB ICC asset and preserves output on cancellation" {
    const icc = fs.read_bytes("src/engine/assets/sRGB2014.icc") catch (error) {
        assert(false);
        return;
    };
    const expected: [32]u8 = [
        0x38, 0x4b, 0x83, 0x2d, 0xe3, 0x41, 0x20, 0x66,
        0x74, 0x3b, 0x52, 0xa7, 0x5e, 0xe9, 0x06, 0xb6,
        0xfb, 0x9f, 0xb8, 0xd9, 0xe0, 0x9e, 0x93, 0x6f,
        0xc2, 0xc4, 0x32, 0x23, 0x81, 0x5c, 0x6e, 0x0a
    ];
    var digest: [32]u8 = [9] ** 32;
    assert(sha256.digest(icc[..], digest[0..], no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 32 {
        assert(digest[index] == expected[index]);
        index = index + 1;
    }
    assert(sha256.digest(icc[..], digest[0..], cancel, 0) == 7);
    assert(digest[0] == expected[0]);
}
