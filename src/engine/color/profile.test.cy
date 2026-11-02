import .engine.color.profile;
import .engine.color.color_matrix;
import .engine.core.sha256;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn base_bytes(): [1584]u8 {
    var bytes: [1584]u8 = [0] ** 1584;
    bytes[0] = 76;
    bytes[1] = 67;
    bytes[2] = 80;
    bytes[3] = 49;
    bytes[4] = 1;
    bytes[8] = 7;
    // Three diagonal IEEE-754 f64 values of 1, little endian.
    bytes[12 + 6] = 240;
    bytes[12 + 7] = 63;
    bytes[12 + 4 * 8 + 6] = 240;
    bytes[12 + 4 * 8 + 7] = 63;
    bytes[12 + 8 * 8 + 6] = 240;
    bytes[12 + 8 * 8 + 7] = 63;
    return bytes;
}

fn digest(bytes: []const u8): [32]u8 {
    var hash: [32]u8 = [0] ** 32;
    assert(sha256.digest(bytes, hash[0..], no_cancel, 0) == 0);
    return hash;
}

test "camera profile matrix maps a representative camera strip into working RGB" {
    const bytes = base_bytes();
    const asset: profile.ProfileAsset = {
        bytes: bytes[0..],
        expected_sha256: digest(bytes[0..])
    };
    assert(profile.validate(&asset, no_cancel, 0) == 0);
    const input: [9]f32 = [1.0, 0.0, 0.0, 0.5, 0.5, 0.5, 2.0, 0.0, 0.0];
    var output: [9]f32 = [9.0] ** 9;
    assert(profile.apply(input[0..], 3, 1, &asset,
        output[0..], no_cancel, 0
    ) == 0);
    const matrix: [9]f64 = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    var pixel: usize = 0;
    while pixel < 3 {
        const expected = color_matrix.camera_to_working(matrix,
            input[pixel * 3] as f64,
            input[pixel * 3 + 1] as f64,
            input[pixel * 3 + 2] as f64
        );
        assert((output[pixel * 3] as f64) > expected.red - 0.00001
            and (output[pixel * 3] as f64) < expected.red + 0.00001
        );
        assert((output[pixel * 3 + 1] as f64) > expected.green - 0.00001
            and (output[pixel * 3 + 1] as f64) < expected.green + 0.00001
        );
        assert((output[pixel * 3 + 2] as f64) > expected.blue - 0.00001
            and (output[pixel * 3 + 2] as f64) < expected.blue + 0.00001
        );
        pixel = pixel + 1;
    }
}

test "camera profile residual LUT is pinned and adds measured working delta" {
    var bytes = base_bytes();
    var node: usize = 0;
    while node < 125 {
        bytes[84 + node * 12 + 3] = 62; // f32 0.125 red residual.
        node = node + 1;
    }
    const hash = digest(bytes[0..]);
    const asset: profile.ProfileAsset = {
        bytes: bytes[0..],
        expected_sha256: hash
    };
    const input: [3]f32 = [0.5, 0.5, 0.5];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    assert(profile.apply(input[0..], 1, 1, &asset,
        output[0..], no_cancel, 0
    ) == 0);
    const matrix: [9]f64 = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    const base = color_matrix.camera_to_working(matrix, 0.5, 0.5, 0.5);
    assert((output[0] as f64) > base.red + 0.12499
        and (output[0] as f64) < base.red + 0.12501
    );
    assert((output[1] as f64) > base.green - 0.00001
        and (output[1] as f64) < base.green + 0.00001
    );
    var changed = bytes;
    changed[84 + 3] = 61;
    const tampered: profile.ProfileAsset = {
        bytes: changed[0..],
        expected_sha256: hash
    };
    assert(profile.validate(&tampered, no_cancel, 0) == 2);
    assert(profile.validate(&asset, cancel, 0) == 7);
}

test "camera profile trilinear residual weights one lattice corner" {
    var bytes = base_bytes();
    bytes[84 + 3] = 62; // Only grid node (0,0,0) has red delta 0.125.
    const asset: profile.ProfileAsset = {
        bytes: bytes[0..],
        expected_sha256: digest(bytes[0..])
    };
    const input: [3]f32 = [0.125, 0.125, 0.125];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    assert(profile.apply(input[0..], 1, 1, &asset,
        output[0..], no_cancel, 0
    ) == 0);
    const matrix: [9]f64 = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    const base = color_matrix.camera_to_working(matrix, 0.125, 0.125, 0.125);
    assert((output[0] as f64) > base.red + 0.01562
        and (output[0] as f64) < base.red + 0.01563
    );
    assert((output[1] as f64) > base.green - 0.00001
        and (output[1] as f64) < base.green + 0.00001
    );
}

test "camera profile clamps residual lookup but retains matrix headroom" {
    var bytes = base_bytes();
    bytes[84 + 3] = 62; // Lower camera-grid corner: red +0.125.
    bytes[84 + 124 * 12 + 3] = 62; // Upper corner: red +0.125.
    const asset: profile.ProfileAsset = {
        bytes: bytes[0..],
        expected_sha256: digest(bytes[0..])
    };
    const input: [6]f32 = [-0.25, -0.25, -0.25, 2.0, 2.0, 2.0];
    var output: [6]f32 = [9.0] ** 6;
    assert(profile.apply(input[0..], 2, 1, &asset,
        output[0..], no_cancel, 0
    ) == 0);
    const matrix: [9]f64 = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    const dark = color_matrix.camera_to_working(matrix, -0.25, -0.25, -0.25);
    const bright = color_matrix.camera_to_working(matrix, 2.0, 2.0, 2.0);
    assert((output[0] as f64) > dark.red + 0.12499
        and (output[0] as f64) < dark.red + 0.12501
    );
    assert((output[3] as f64) > bright.red + 0.12499
        and (output[3] as f64) < bright.red + 0.12501
    );
}

test "camera profile rejects malformed assets and input shape" {
    const bytes = base_bytes();
    const hash = digest(bytes[0..]);
    const asset: profile.ProfileAsset = {
        bytes: bytes[0..],
        expected_sha256: hash
    };
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    assert(profile.apply(input[0..], 0, 1, &asset,
        output[0..], no_cancel, 0
    ) == 3);
    const bad: [3]f32 = [9.0, 0.3, 0.4];
    assert(profile.apply(bad[0..], 1, 1, &asset,
        output[0..], no_cancel, 0
    ) == 4);
    var malformed = bytes;
    malformed[0] = 0;
    const wrong: profile.ProfileAsset = {
        bytes: malformed[0..],
        expected_sha256: hash
    };
    assert(profile.validate(&wrong, no_cancel, 0) == 1);
    assert(output[0] == 9.0);
}
