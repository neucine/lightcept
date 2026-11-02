import .engine.develop.dehaze;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): dehaze.HazeAsset {
    return {
        version: 1,
        atmospheric_light: [1.0, 1.0, 1.0],
        minimum_transmission: 0.1,
        strength: 1.0,
        maximum_change: 1.0
    };
}

test "dehaze inverts an analytical atmospheric mixture" {
    const input: [6]f32 = [0.6, 0.7, 0.8, 0.6, 0.7, 0.8];
    const transmission: [2]f32 = [0.5, 1.0];
    var output: [6]f32 = [9.0] ** 6;
    assert(dehaze.apply(input[0..], transmission[0..], 2, 1,
        settings(), output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > 0.199 and output[0] < 0.201);
    assert(output[1] > 0.399 and output[1] < 0.401);
    assert(output[2] > 0.599 and output[2] < 0.601);
    assert(output[3] == input[3] and output[5] == input[5]);
}

test "dehaze preserves disabled image and caps strong inversion" {
    const input: [3]f32 = [-0.1, 0.2, 1.5];
    const transmission: [1]f32 = [0.1];
    var output: [3]f32 = [9.0] ** 3;
    var disabled = settings();
    disabled.strength = 0.0;
    assert(dehaze.apply(input[0..], transmission[0..], 1, 1,
        disabled, output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[2] == input[2]);
    var limited = settings();
    limited.maximum_change = 0.05;
    assert(dehaze.apply(input[0..], transmission[0..], 1, 1,
        limited, output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > -0.151 and output[0] < -0.149);
    assert(output[2] > 1.549 and output[2] < 1.551);
}

test "dehaze rejects missing estimates nonfinite values and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    const transmission: [1]f32 = [0.5];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings();
    bad.minimum_transmission = 0.0;
    assert(dehaze.apply(input[0..], transmission[0..], 1, 1,
        bad, output[0..], no_cancel, 0
    ) == 1);
    assert(dehaze.apply(input[0..], transmission[0..], 2, 1,
        settings(), output[0..], no_cancel, 0
    ) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    assert(dehaze.apply(nonfinite[0..], transmission[0..], 1, 1,
        settings(), output[0..], no_cancel, 0
    ) == 3);
    const wrong: [1]f32 = [0.01];
    assert(dehaze.apply(input[0..], wrong[0..], 1, 1,
        settings(), output[0..], no_cancel, 0
    ) == 4);
    assert(dehaze.apply(input[0..], transmission[0..], 1, 1,
        settings(), output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[2] == 9.0);
}
