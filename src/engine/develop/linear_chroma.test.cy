import .engine.develop.linear_chroma;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "linear chroma preserves Rec.2020 luminance and signed headroom" {
    const red = -0.25 as f64;
    const green = 0.4 as f64;
    const blue = 1.5 as f64;
    const baseline = 0.2627 * (red as f64) + 0.6780 * (green as f64) + 0.0593 * (blue as f64);
    const neutral = linear_chroma.apply(red, green, blue, 1.0);
    assert(neutral.red == red and neutral.green == green and neutral.blue == blue);
    const zero = linear_chroma.apply(red, green, blue, 0.0);
    assert(zero.red == zero.green and zero.green == zero.blue);
    const vivid = linear_chroma.apply(red, green, blue, 1.5);
    const y = 0.2627 * (vivid.red as f64) + 0.6780 * (vivid.green as f64) + 0.0593 * (vivid.blue as f64);
    const error = y - baseline;
    assert(error * error < 0.000000000001);
    assert((vivid.red as f64) < 0.0 and (vivid.blue as f64) > 1.0);
}

test "linear chroma image keeps greys and scales colorful signed strip" {
    const input: [9]f32 = [0.18, 0.18, 0.18,
        -0.25, 0.4, 1.5, 8.0, 0.0, 0.0
    ];
    var output: [9]f32 = [99.0] ** 9;
    const asset: linear_chroma.LinearChromaAsset = {
        version: 1,
        factor: 2.0
    };
    assert(linear_chroma.apply_image(input[0..], 3, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > 0.17999 and (output[0] as f64) < 0.18001);
    assert(output[3] < -0.25 and output[5] > 1.5 and output[6] > 8.0);
    const before = 0.2627 * (input[3] as f64)
    + 0.6780 * (input[4] as f64) + 0.0593 * (input[5] as f64);
    const after = 0.2627 * (output[3] as f64)
    + 0.6780 * (output[4] as f64) + 0.0593 * (output[5] as f64);
    assert(after > before - 0.000001 and after < before + 0.000001);
}

test "linear chroma image validates factor source shape and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [99.0] ** 3;
    const asset: linear_chroma.LinearChromaAsset = {
        version: 1,
        factor: 1.0
    };
    assert(linear_chroma.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.3, 0.4];
    assert(linear_chroma.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(linear_chroma.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: linear_chroma.LinearChromaAsset = {
        version: 1,
        factor: 2.1
    };
    assert(linear_chroma.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}
