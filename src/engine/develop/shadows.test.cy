import .engine.develop.shadows;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "shadow band has exact neutral and endpoint identities" {
    const neutral = shadows.apply(-0.2, 0.09, 1.4, 0.0);
    assert(neutral.red == -0.2 and neutral.green == 0.09 and neutral.blue == 1.4);
    const black = shadows.apply(0.0, 0.0, 0.0, 1.0);
    assert(black.red == 0.0 and black.green == 0.0 and black.blue == 0.0);
    const middle = shadows.apply(0.18, 0.18, 0.18, 1.0);
    assert(middle.red == 0.18 and middle.green == 0.18 and middle.blue == 0.18);
    const signed = shadows.apply(-0.1, -0.1, -0.1, 1.0);
    assert(signed.red == -0.1);
    const headroom = shadows.apply(2.0, 2.0, 2.0, 1.0);
    assert(headroom.red == 2.0);
}

test "shadow image preserves signed and highlight samples across a strip" {
    const input: [12]f32 = [-0.1, -0.1, -0.1,
        0.09, 0.09, 0.09, 0.18, 0.18, 0.18,
        2.0, 2.0, 2.0
    ];
    var output: [12]f32 = [9.0] ** 12;
    const asset: shadows.ShadowsAsset = {
        version: 1,
        strength: 1.0
    };
    assert(shadows.apply_image(input[0..], 4, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > -0.10001 and (output[0] as f64) < -0.09999);
    assert((output[3] as f64) > 0.13499 and (output[3] as f64) < 0.13501);
    assert((output[6] as f64) > 0.17999 and (output[6] as f64) < 0.18001);
    assert((output[9] as f64) > 1.99999 and (output[9] as f64) < 2.00001);
}

test "shadow image validates asset shape samples and cancellation" {
    const input: [3]f32 = [0.09, 0.09, 0.09];
    var output: [3]f32 = [9.0] ** 3;
    const asset: shadows.ShadowsAsset = {
        version: 1,
        strength: 1.0
    };
    assert(shadows.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.09, 0.09];
    assert(shadows.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(shadows.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: shadows.ShadowsAsset = {
        version: 1,
        strength: 1.1
    };
    assert(shadows.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 9.0);
}

test "shadow band is monotone on analytical greys and preserves chroma" {
    const low = shadows.apply(0.045, 0.045, 0.045, 1.0);
    const middle = shadows.apply(0.09, 0.09, 0.09, 1.0);
    assert(middle.red > 0.134999 and middle.red < 0.135001);
    const high = shadows.apply(0.135, 0.135, 0.135, 1.0);
    assert(low.red > 0.045 and low.red < middle.red and middle.red < high.red and high.red < 0.18);
    const darkened = shadows.apply(0.09, 0.09, 0.09, -1.0);
    assert(darkened.red > 0.0 and darkened.red < 0.09);
    const color = shadows.apply(0.16, 0.08, 0.02, 0.5);
    assert(color.red - color.green > 0.079999 and color.red - color.green < 0.080001);
    assert(shadows.valid_strength(-1.0) and shadows.valid_strength(1.0));
    assert(not shadows.valid_strength(-1.01) and not shadows.valid_strength(1.01));
}
