import .engine.develop.channel_mixer;
import .engine.color.output_color;

test "neutral mixer is exact identity for signed channels and headroom" {
    const result = channel_mixer.apply(channel_mixer.neutral_asset(), -0.2, 0.18, 1.5);
    assert(result.valid and result.status == 0);
    assert(result.red == -0.2 and result.green == 0.18 and result.blue == 1.5);
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
    const infinity = output_color.exposure_gain_native(1024.0);
    const bad_input = channel_mixer.apply(channel_mixer.neutral_asset(), infinity, 0.3, 0.4);
    assert(not bad_input.valid and bad_input.status == 2);
}
