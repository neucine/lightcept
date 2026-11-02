import .engine.develop.whites;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "whites pivot and neutral are exact and analytical greys retain headroom" {
    const neutral = whites.apply(-0.2, 0.7, 2.0, 0.0);
    assert(neutral.red == -0.2 and neutral.green == 0.7 and neutral.blue == 2.0);
    const pivot = whites.apply(0.5, 0.5, 0.5, 1.0);
    assert(pivot.red == 0.5 and pivot.green == 0.5 and pivot.blue == 0.5);
    const shadow = whites.apply(-0.2, -0.2, -0.2, 1.0);
    assert(shadow.red == -0.2);
    const white = whites.apply(1.0, 1.0, 1.0, 1.0);
    assert(white.red == 1.5 and white.green == 1.5 and white.blue == 1.5);
    const lowered = whites.apply(1.0, 1.0, 1.0, -0.5);
    assert(lowered.red == 0.75);
    const headroom = whites.apply(2.0, 2.0, 2.0, 1.0);
    assert(headroom.red == 3.5);
}

test "white image uses half-white pivot and retains signed chroma" {
    const input: [12]f32 = [-0.1, -0.1, -0.1,
        0.5, 0.5, 0.5, 1.0, 1.0, 1.0,
        2.0, 2.0, 2.0
    ];
    var output: [12]f32 = [99.0] ** 12;
    const asset: whites.WhitesAsset = {
        version: 1,
        strength: 1.0
    };
    assert(whites.apply_image(input[0..], 4, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > -0.10001 and (output[0] as f64) < -0.09999);
    assert((output[3] as f64) > 0.49999 and (output[3] as f64) < 0.50001);
    assert((output[6] as f64) > 1.49999 and (output[6] as f64) < 1.50001);
    assert((output[9] as f64) > 3.49999 and (output[9] as f64) < 3.50001);
}

test "white image checks asset source shape and cancellation" {
    const input: [3]f32 = [1.0, 1.0, 1.0];
    var output: [3]f32 = [99.0] ** 3;
    const asset: whites.WhitesAsset = {
        version: 1,
        strength: 1.0
    };
    assert(whites.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 1.0, 1.0];
    assert(whites.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(whites.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: whites.WhitesAsset = {
        version: 2,
        strength: 1.0
    };
    assert(whites.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}

test "whites preserves channel differences and validates strength" {
    const color = whites.apply(1.0, 0.7, 0.4, 0.5);
    assert(color.red - color.green > 0.299999 and color.red - color.green < 0.300001);
    assert(whites.valid_strength(-0.5) and whites.valid_strength(1.0));
    assert(not whites.valid_strength(-0.51) and not whites.valid_strength(1.01));
}
