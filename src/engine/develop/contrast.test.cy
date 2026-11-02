import .engine.develop.contrast;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "contrast preserves neutral identity, pivot, chroma and headroom" {
    const neutral = contrast.apply(-0.2, 0.18, 1.4, 1.0);
    assert(neutral.red == -0.2 and neutral.green == 0.18 and neutral.blue == 1.4);
    const pivot = contrast.apply(0.18, 0.18, 0.18, 2.0);
    assert(pivot.red == 0.18 and pivot.green == 0.18 and pivot.blue == 0.18);
    const dark = contrast.apply(0.0, 0.0, 0.0, 2.0);
    const bright = contrast.apply(1.5, 1.5, 1.5, 2.0);
    assert(dark.red < 0.0 and bright.red > 1.5);
    const color = contrast.apply(0.8, 0.2, -0.1, 1.5);
    assert(color.red - color.green > 0.599999 and color.red - color.green < 0.600001);
    assert(contrast.valid_slope(0.5) and contrast.valid_slope(2.0));
    assert(not contrast.valid_slope(0.49) and not contrast.valid_slope(2.01));
    assert(contrast.slope_from_percent(-100.0) == 0.5);
    assert(contrast.slope_from_percent(0.0) == 1.0);
    assert(contrast.slope_from_percent(100.0) == 2.0);
}

test "contrast image retains signed range pivot chroma and headroom" {
    const input: [12]f32 = [-0.25, -0.25, -0.25,
        0.18, 0.18, 0.18, 0.8, 0.2, 0.0,
        2.0, 2.0, 2.0
    ];
    var output: [12]f32 = [99.0] ** 12;
    const asset: contrast.ContrastAsset = {
        version: 1,
        slope: 2.0
    };
    assert(contrast.apply_image(input[0..], 4, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > -0.681 and (output[0] as f64) < -0.679);
    assert((output[3] as f64) > 0.17999 and (output[3] as f64) < 0.18001);
    assert((output[6] as f64) - (output[7] as f64) > 0.59999
        and (output[6] as f64) - (output[7] as f64) < 0.60001
    );
    assert((output[9] as f64) > 3.81999 and (output[9] as f64) < 3.82001);
}

test "contrast image rejects invalid slope source shape and cancellation" {
    const input: [3]f32 = [0.18, 0.18, 0.18];
    var output: [3]f32 = [99.0] ** 3;
    const asset: contrast.ContrastAsset = {
        version: 1,
        slope: 2.0
    };
    assert(contrast.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.18, 0.18];
    assert(contrast.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(contrast.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: contrast.ContrastAsset = {
        version: 1,
        slope: 2.1
    };
    assert(contrast.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}
