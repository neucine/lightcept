import .engine.core.core;
import .engine.develop.channel_mixer;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "neutral mixer is exact identity for signed channels and headroom" {
    const result = channel_mixer.apply(channel_mixer.neutral_asset(), -0.2, 0.18, 1.5);
    assert(result.valid and result.status == 0);
    assert(result.red == -0.2 and result.green == 0.18 and result.blue == 1.5);
}

test "channel mixer image swaps red green across a scene strip" {
    var asset = channel_mixer.neutral_asset();
    asset.red_from_green = 1.0;
    asset.green_from_red = 1.0;
    const input: [9]f32 = [0.18, 0.18, 0.18,
        0.8, 0.2, 0.4, -0.2, 1.5, 2.0
    ];
    var output: [9]f32 = [99.0] ** 9;
    assert(channel_mixer.apply_image(input[0..], 3, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > 0.17999 and (output[0] as f64) < 0.18001);
    assert((output[3] as f64) > 0.19999 and (output[3] as f64) < 0.20001);
    assert((output[4] as f64) > 0.79999 and (output[4] as f64) < 0.80001);
    assert((output[6] as f64) > 1.49999 and (output[6] as f64) < 1.50001);
    assert((output[7] as f64) > -0.20001 and (output[7] as f64) < -0.19999);
}

test "channel mixer image validates asset source shape and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [99.0] ** 3;
    const asset = channel_mixer.neutral_asset();
    assert(channel_mixer.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.3, 0.4];
    assert(channel_mixer.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(channel_mixer.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    var invalid = asset;
    invalid.red_from_blue = 1.1;
    assert(channel_mixer.apply_image(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}

test "cross-channel coefficients give an analytical red green swap" {
    var asset = channel_mixer.neutral_asset();
    asset.red_from_green = 1.0;
    asset.green_from_red = 1.0;
    assert(channel_mixer.valid(asset));
    const swapped = channel_mixer.apply(asset, 0.8, 0.2, 0.4);
    assert(swapped.valid and swapped.red > 0.199999 and swapped.red < 0.200001);
    assert(swapped.green > 0.799999 and swapped.green < 0.800001 and swapped.blue == 0.4);
    const neutral = channel_mixer.apply(asset, 0.18, 0.18, 0.18);
    assert(neutral.red == 0.18 and neutral.green == 0.18 and neutral.blue == 0.18);
}

test "mixer rejects invalid coefficients and nonfinite samples" {
    var asset = channel_mixer.neutral_asset();
    asset.blue_from_red = 1.01;
    const invalid = channel_mixer.apply(asset, 0.2, 0.3, 0.4);
    assert(not invalid.valid and invalid.status == 1);
    const infinity = core.positive_infinity64();
    const bad_input = channel_mixer.apply(channel_mixer.neutral_asset(), infinity, 0.3, 0.4);
    assert(not bad_input.valid and bad_input.status == 2);
}
