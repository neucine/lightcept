import .engine.develop.vibrance;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "linear vibrance has exact neutral identity and retains luminance" {
    const original = vibrance.apply(-0.2, 0.18, 1.4, 0.0);
    assert(original.red == -0.2 and original.green == 0.18 and original.blue == 1.4);
    const grey = vibrance.apply(0.18, 0.18, 0.18, 1.0);
    assert(grey.red == 0.18 and grey.green == 0.18 and grey.blue == 0.18);
    const changed = vibrance.apply(0.8, 0.2, 0.2, 0.75);
    const before_y = 0.2627 * 0.8 + 0.6780 * 0.2 + 0.0593 * 0.2;
    const after_y = 0.2627 * (changed.red as f64) + 0.6780 * (changed.green as f64) + 0.0593 * (changed.blue as f64);
    assert(after_y > before_y - 0.000001 and after_y < before_y + 0.000001);
    assert(changed.red > 0.8 and changed.green < 0.2);
}

test "vibrance image prioritizes subtle chroma in a signed color strip" {
    const input: [12]f32 = [0.18, 0.18, 0.18,
        0.3, 0.2, 0.2, 0.8, 0.2, 0.2,
        -0.2, 0.2, 1.5
    ];
    var output: [12]f32 = [99.0] ** 12;
    const asset: vibrance.VibranceAsset = {
        version: 1,
        strength: 1.0
    };
    assert(vibrance.apply_image(input[0..], 4, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > 0.17999 and (output[0] as f64) < 0.18001);
    assert(output[3] > input[3] and output[6] > input[6]);
    const low_gain = ((output[3] as f64) - (output[4] as f64)) / 0.1;
    const high_gain = ((output[6] as f64) - (output[7] as f64)) / 0.6;
    assert(low_gain > high_gain);
    assert(output[9] < -0.2 and output[11] > 1.5);
}

test "vibrance image checks asset shape source and cancellation" {
    const input: [3]f32 = [0.3, 0.2, 0.2];
    var output: [3]f32 = [99.0] ** 3;
    const asset: vibrance.VibranceAsset = {
        version: 1,
        strength: 1.0
    };
    assert(vibrance.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.2, 0.2];
    assert(vibrance.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(vibrance.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: vibrance.VibranceAsset = {
        version: 1,
        strength: 1.1
    };
    assert(vibrance.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}

test "linear vibrance prioritizes low chroma and preserves hue direction" {
    const low = vibrance.apply(0.3, 0.2, 0.2, 1.0);
    const high = vibrance.apply(0.8, 0.2, 0.2, 1.0);
    assert((low.red - low.green) / 0.1 > (high.red - high.green) / 0.6);
    assert(low.red > low.green and high.red > high.green);
    const less = vibrance.apply(0.8, 0.2, 0.2, -1.0);
    assert(less.red > less.green and less.red - less.green < 0.6);
    const signed = vibrance.apply(-0.2, 0.2, 1.5, 0.5);
    assert(signed.red < 0.0 and signed.blue > 1.5);
    assert(vibrance.valid_strength(-1.0) and vibrance.valid_strength(1.0));
    assert(not vibrance.valid_strength(-1.01) and not vibrance.valid_strength(1.01));
}
