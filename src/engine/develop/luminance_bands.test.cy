import .engine.core.core;
import .engine.develop.luminance_bands;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "neutral bands preserve signed representative RGB and headroom" {
    const result = luminance_bands.apply(luminance_bands.neutral_asset(), -0.2, 0.18, 1.5);
    assert(result.valid and result.red == -0.2 and result.green == 0.18 and result.blue == 1.5);
}

test "luminance band image retains signed values and headroom across anchors" {
    const asset: luminance_bands.BandAsset = {
        version: 1,
        black_ev: 1.0,
        middle_ev: 0.0,
        white_ev: -1.0
    };
    const input: [12]f32 = [-0.1, -0.1, -0.1,
        0.09, 0.09, 0.09, 0.18, 0.18, 0.18,
        2.0, 2.0, 2.0
    ];
    var output: [12]f32 = [99.0] ** 12;
    assert(luminance_bands.apply_image(input[0..], 4, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > -0.20001 and (output[0] as f64) < -0.19999);
    assert((output[3] as f64) > 0.12727 and (output[3] as f64) < 0.12729);
    assert((output[6] as f64) > 0.17999 and (output[6] as f64) < 0.18001);
    assert((output[9] as f64) > 0.99999 and (output[9] as f64) < 1.00001);
}

test "luminance band image rejects invalid asset source and cancellation" {
    const asset = luminance_bands.neutral_asset();
    const input: [3]f32 = [0.2, 0.2, 0.2];
    var output: [3]f32 = [99.0] ** 3;
    assert(luminance_bands.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.2, 0.2];
    assert(luminance_bands.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(luminance_bands.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    const invalid: luminance_bands.BandAsset = {
        version: 1,
        black_ev: 5.0,
        middle_ev: 0.0,
        white_ev: 0.0
    };
    assert(luminance_bands.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}

test "three anchors and interpolation select declared EV" {
    const asset: luminance_bands.BandAsset = {
        version: 1,
        black_ev: 1.0,
        middle_ev: 0.0,
        white_ev: -1.0
    };
    const black = luminance_bands.apply(asset, -0.1, -0.1, -0.1);
    assert(black.valid and black.red > -0.200001 and black.red < -0.199999);
    const middle = luminance_bands.apply(asset, 0.18, 0.18, 0.18);
    assert(middle.valid and middle.red > 0.179999 and middle.red < 0.180001);
    const white = luminance_bands.apply(asset, 1.5, 1.5, 1.5);
    assert(white.valid and white.red > 0.749999 and white.red < 0.750001);
    const halfway = luminance_bands.apply(asset, 0.09, 0.09, 0.09);
    const expected = 0.09 * output_color.exposure_gain_native(0.5);
    assert(halfway.valid and halfway.red > expected - 0.000001 and halfway.red < expected + 0.000001);
}

test "bands preserve RGB ratios and reject invalid data" {
    const asset: luminance_bands.BandAsset = {
        version: 1,
        black_ev: 0.0,
        middle_ev: 1.0,
        white_ev: 0.0
    };
    const color = luminance_bands.apply(asset, 0.3, 0.15, 0.06);
    assert(color.valid and color.red > color.green and color.green > color.blue);
    assert(color.red - color.green * 2.0 < 0.0000001 and color.red - color.green * 2.0 > -0.0000001);
    const invalid: luminance_bands.BandAsset = {
        version: 2,
        black_ev: 0.0,
        middle_ev: 0.0,
        white_ev: 0.0
    };
    assert(luminance_bands.apply(invalid, 0.2, 0.2, 0.2).status == 1);
    const infinity = core.positive_infinity64();
    assert(luminance_bands.apply(asset, infinity, 0.2, 0.2).status == 2);
}
