import .engine.develop.raw_denoise;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn noise(): raw_denoise.SensorNoiseAsset {
    return {
        version: 1,
        cfa: [0, 1, 1, 2],
        read_sigma: [0.1, 0.1, 0.1],
        shot_variance: [0.0, 0.0, 0.0],
        strength: 1.0,
        maximum_change: 0.05
    };
}

test "raw denoise preserves constant Bayer mosaic and disabled input" {
    const input: [16]f32 = [0.18] ** 16;
    var output: [16]f32 = [9.0] ** 16;
    assert(raw_denoise.apply(input[0..], 4, 4, noise(), output[0..], no_cancel, 0) == 0);
    assert(output[0] == 0.18 and output[15] == 0.18);
    var disabled = noise();
    disabled.strength = 0.0;
    const varied: [4]f32 = [-0.1, 0.2, 1.5, 0.4];
    var unchanged: [4]f32 = [9.0] ** 4;
    assert(raw_denoise.apply(varied[0..], 2, 2, disabled,
        unchanged[0..], no_cancel, 0
    ) == 0);
    assert(unchanged[0] == varied[0] and unchanged[2] == varied[2]);
}

test "raw denoise uses same CFA phase and caps isolated change" {
    var input: [25]f32 = [0.0] ** 25;
    input[0] = 0.2;
    input[2] = 0.18;
    input[10] = 0.18;
    input[12] = 1.0;
    var output: [25]f32 = [9.0] ** 25;
    assert(raw_denoise.apply(input[0..], 5, 5, noise(), output[0..], no_cancel, 0) == 0);
    assert(output[0] > 0.18 and output[0] < 0.2);
    assert(output[12] >= 0.95 and output[12] <= 1.0);
    assert(output[1] == 0.0);
}

test "raw denoise rejects invalid asset shape input and cancellation" {
    const input: [4]f32 = [0.1, 0.2, 0.3, 0.4];
    var output: [4]f32 = [9.0] ** 4;
    var bad = noise();
    bad.cfa = [0, 0, 1, 2];
    assert(raw_denoise.apply(input[0..], 2, 2, bad, output[0..], no_cancel, 0) == 1);
    bad.cfa = [0, 1, 2, 1];
    assert(raw_denoise.apply(input[0..], 2, 2, bad, output[0..], no_cancel, 0) == 1);
    bad = noise();
    bad.read_sigma[0] = output_color.exposure_gain_native(1024.0);
    assert(raw_denoise.apply(input[0..], 2, 2, bad, output[0..], no_cancel, 0) == 1);
    assert(raw_denoise.apply(input[0..], 3, 2, noise(), output[0..], no_cancel, 0) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [4]f32 = [infinity, 0.2, 0.3, 0.4];
    assert(raw_denoise.apply(nonfinite[0..], 2, 2, noise(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(raw_denoise.apply(input[0..], 2, 2, noise(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[3] == 9.0);
}
