import .engine.develop.highlights;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "highlight band has exact neutral and endpoint identities" {
    const neutral = highlights.apply(-0.2, 0.6, 1.4, 0.0);
    assert(neutral.red == -0.2 and neutral.green == 0.6 and neutral.blue == 1.4);
    const pivot = highlights.apply(0.18, 0.18, 0.18, -1.0);
    assert(pivot.red == 0.18 and pivot.green == 0.18 and pivot.blue == 0.18);
    const white = highlights.apply(1.0, 1.0, 1.0, -1.0);
    assert(white.red == 1.0);
    const headroom = highlights.apply(2.0, 2.0, 2.0, -1.0);
    assert(headroom.red == 2.0);
    const signed = highlights.apply(-0.25, -0.25, -0.25, 1.0);
    assert(signed.red == -0.25);
}

test "highlight image retains signed shadows and headroom around its band" {
    const input: [12]f32 = [-0.1, -0.1, -0.1,
        0.18, 0.18, 0.18, 0.59, 0.59, 0.59,
        2.0, 2.0, 2.0
    ];
    var output: [12]f32 = [9.0] ** 12;
    const asset: highlights.HighlightsAsset = {
        version: 1,
        strength: -1.0
    };
    assert(highlights.apply_image(input[0..], 4, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > -0.10001 and (output[0] as f64) < -0.09999);
    assert((output[3] as f64) > 0.17999 and (output[3] as f64) < 0.18001);
    assert((output[6] as f64) > 0.38499 and (output[6] as f64) < 0.38501);
    assert((output[9] as f64) > 1.99999 and (output[9] as f64) < 2.00001);
}

test "highlight image rejects invalid values and cancellation before writes" {
    const input: [3]f32 = [0.59, 0.59, 0.59];
    var output: [3]f32 = [9.0] ** 3;
    const asset: highlights.HighlightsAsset = {
        version: 1,
        strength: 1.0
    };
    assert(highlights.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.59, 0.59];
    assert(highlights.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(highlights.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: highlights.HighlightsAsset = {
        version: 1,
        strength: -1.1
    };
    assert(highlights.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 9.0);
}

test "highlight band is monotone and preserves chroma" {
    const low = highlights.apply(0.385, 0.385, 0.385, -1.0);
    const middle = highlights.apply(0.59, 0.59, 0.59, -1.0);
    assert(middle.red > 0.384999 and middle.red < 0.385001);
    const high = highlights.apply(0.795, 0.795, 0.795, -1.0);
    assert(low.red > 0.18 and low.red < middle.red and middle.red < high.red and high.red < 1.0);
    const lifted = highlights.apply(0.59, 0.59, 0.59, 1.0);
    assert(lifted.red > 0.59 and lifted.red < 1.0);
    const color = highlights.apply(0.8, 0.5, 0.2, -0.5);
    assert(color.red - color.green > 0.299999 and color.red - color.green < 0.300001);
    assert(highlights.valid_strength(-1.0) and highlights.valid_strength(1.0));
    assert(not highlights.valid_strength(-1.01) and not highlights.valid_strength(1.01));
}
