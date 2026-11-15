import .engine.core.core;
import .engine.develop.vignetting;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): vignetting.VignettingAsset {
    return {
        version: 1,
        model_hash: 1,
        center_x_fraction: 0.5,
        center_y_fraction: 0.5,
        k1: -0.2,
        k2: 0.0,
        k3: 0.0,
        strength: 1.0,
        maximum_gain: 4.0
    };
}

test "vignetting applies a radial linear-light gain" {
    const input: [27]f32 = [0.4] ** 27;
    var output: [27]f32 = [9.0] ** 27;
    assert(vignetting.apply(input[0..], 3, 3, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[12] == input[12]);
    assert(output[0] > 0.499 and output[0] < 0.501);
    assert(output[3] > 0.443 and output[3] < 0.445);
    assert(output[0] == output[24]);
    assert(vignetting.gain(3, 3, settings(), 1, 1) == 1.0);
}

test "vignetting preserves disabled HDR and caps corner gain" {
    const input: [12]f32 = [-0.1, 0.2, 1.5, 0.2, 0.3, 0.4,
        0.5, 0.6, 0.7, 0.8, 0.9, 1.0
    ];
    var output: [12]f32 = [9.0] ** 12;
    var disabled = settings();
    disabled.strength = 0.0;
    assert(vignetting.apply(input[0..], 2, 2, disabled,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[2] == input[2]);
    var capped = settings();
    capped.k1 = -0.25;
    capped.k2 = -0.25;
    capped.k3 = -0.25;
    capped.maximum_gain = 2.0;
    assert(vignetting.apply(input[0..], 2, 2, capped,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == -0.2 and output[2] == 3.0);
}

test "vignetting rejects asset shape input and cancellation" {
    const input: [12]f32 = [0.2] ** 12;
    var output: [12]f32 = [9.0] ** 12;
    var bad = settings();
    bad.model_hash = 0;
    assert(vignetting.apply(input[0..], 2, 2, bad,
        output[0..], no_cancel, 0
    ) == 1);
    assert(vignetting.apply(input[0..], 2, 2, settings(),
        output[0..3], no_cancel, 0
    ) == 2);
    const infinity = core.positive_infinity32();
    var nonfinite: [12]f32 = [0.2] ** 12;
    nonfinite[0] = infinity;
    assert(vignetting.apply(nonfinite[0..], 2, 2, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(vignetting.apply(input[0..], 2, 2, settings(),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[11] == 9.0);
}
