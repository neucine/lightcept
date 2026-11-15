import .engine.core.core;
import .engine.develop.capture_sharpening;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn asset(): capture_sharpening.SharpenAsset {
    return {
        version: 1,
        radius_pixels: 1,
        amount: 1.0,
        threshold_y: 0.0,
        maximum_offset_y: 0.25
    };
}

test "capture sharpening is exact identity when disabled or flat" {
    const input: [12]f32 = [0.18] ** 12;
    var output: [12]f32 = [9.0] ** 12;
    var settings = asset();
    settings.amount = 0.0;
    assert(capture_sharpening.apply(input[0..], 2, 2, settings,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[11] == input[11]);
    settings.amount = 1.0;
    assert(capture_sharpening.apply(input[0..], 2, 2, settings,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[11] == input[11]);
}

test "isolated bright detail uses Gaussian radius and bounded halo" {
    var input: [75]f32 = [0.0] ** 75;
    const center = (2 * 5 + 2) * 3;
    input[center] = 1.0;
    input[center + 1] = 1.0;
    input[center + 2] = 1.0;
    var output: [75]f32 = [9.0] ** 75;
    assert(capture_sharpening.apply(input[0..], 5, 5, asset(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[center] > 1.249999 and output[center] < 1.250001);
    assert(output[center - 3] < 0.0 and output[center - 3] > -0.126);
    assert(output[0] == 0.0);
}

test "threshold suppresses low detail and preserves channel differences" {
    const input: [9]f32 = [0.1, 0.2, 0.3, 0.11, 0.21, 0.31,
        0.1, 0.2, 0.3
    ];
    var output: [9]f32 = [9.0] ** 9;
    var settings = asset();
    settings.threshold_y = 0.1;
    assert(capture_sharpening.apply(input[0..], 3, 1, settings,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[3] == input[3] and output[4] == input[4] and output[5] == input[5]);
}

test "radius two uses the declared five-tap Gaussian support" {
    var input: [75]f32 = [0.0] ** 75;
    const center = (2 * 5 + 2) * 3;
    input[center] = 1.0;
    input[center + 1] = 1.0;
    input[center + 2] = 1.0;
    var output: [75]f32 = [9.0] ** 75;
    var settings = asset();
    settings.radius_pixels = 2;
    settings.amount = 0.25;
    settings.maximum_offset_y = 0.5;
    assert(capture_sharpening.apply(input[0..], 5, 5, settings,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[center] > 1.214843 and output[center] < 1.214845);
}

test "capture sharpening validates asset shape samples and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    var invalid = asset();
    invalid.radius_pixels = 3;
    assert(capture_sharpening.apply(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(capture_sharpening.apply(input[0..], 2, 1, asset(),
        output[0..], no_cancel, 0
    ) == 2);
    const infinity = core.positive_infinity32();
    const bad: [3]f32 = [infinity, 0.2, 0.3];
    assert(capture_sharpening.apply(bad[0..], 1, 1, asset(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(capture_sharpening.apply(input[0..], 1, 1, asset(),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[1] == 9.0 and output[2] == 9.0);
}
