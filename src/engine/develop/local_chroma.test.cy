import .engine.develop.local_chroma;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(factor: f64): local_chroma.LocalChromaAsset {
    return {
        version: 1,
        factor: factor,
        mask_hash: 27
    };
}

test "masked chroma preserves luminance and weights the adjustment" {
    const input: [9]f32 = [0.6, 0.2, 0.2,
        0.6, 0.2, 0.2,
        0.6, 0.2, 0.2
    ];
    const mask: [3]f32 = [0.0, 0.5, 1.0];
    var output: [9]f32 = [9.0] ** 9;
    assert(local_chroma.apply(input[0..], mask[0..], 3, 1,
        settings(0.0), output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[1] == input[1]);
    assert(output[3] > output[6] and output[3] < input[3]);
    assert(output[6] > 0.30 and output[6] < 0.31);
    assert(output[6] == output[7] and output[7] == output[8]);
}

test "local chroma neutral is exact for signed channels and headroom" {
    const input: [6]f32 = [-0.2, 0.2, 1.5, 0.4, 0.6, 2.0];
    const mask: [2]f32 = [1.0, 0.5];
    var output: [6]f32 = [9.0] ** 6;
    assert(local_chroma.apply(input[0..], mask[0..], 2, 1,
        settings(1.0), output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[5] == input[5]);
}

test "local chroma rejects asset shape coverage input and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    const mask: [1]f32 = [1.0];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings(1.5);
    bad.mask_hash = 0;
    assert(local_chroma.apply(input[0..], mask[0..], 1, 1,
        bad, output[0..], no_cancel, 0
    ) == 1);
    assert(local_chroma.apply(input[0..], mask[0..], 2, 1,
        settings(1.5), output[0..], no_cancel, 0
    ) == 2);
    const bad_mask: [1]f32 = [1.5];
    assert(local_chroma.apply(input[0..], bad_mask[0..], 1, 1,
        settings(1.5), output[0..], no_cancel, 0
    ) == 3);
    assert(local_chroma.apply(input[0..], mask[0..], 1, 1,
        settings(1.5), output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
