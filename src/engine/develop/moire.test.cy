import .engine.develop.moire;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): moire.MoireAsset {
    return {
        version: 1,
        cfa: [0, 1, 1, 2],
        minimum_chroma_amplitude: 0.02,
        maximum_luminance_amplitude: 0.05,
        strength: 1.0,
        maximum_change: 0.1
    };
}

test "moire leaves constant color and disabled images exact" {
    const uniform: [27]f32 = [0.3] ** 27;
    var output: [27]f32 = [9.0] ** 27;
    assert(moire.apply(uniform[0..], 3, 3, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == uniform[0] and output[26] == uniform[26]);
    var disabled = settings();
    disabled.strength = 0.0;
    const varied: [3]f32 = [-0.1, 0.3, 1.5];
    var unchanged: [3]f32 = [9.0] ** 3;
    assert(moire.apply(varied[0..], 1, 1, disabled,
        unchanged[0..], no_cancel, 0
    ) == 0);
    assert(unchanged[0] == varied[0] and unchanged[2] == varied[2]);
}

test "moire reduces Bayer-frequency chroma and preserves neutral detail" {
    var input: [147]f32 = [0.5] ** 147;
    var y: usize = 0;
    while y < 7 {
        var x: usize = 0;
        while x < 7 {
            const index = (y * 7 + x) * 3;
            if (x + y) % 2 == 1 {
                input[index] = 0.6;
                input[index + 2] = 0.4;
            } else {
                input[index] = 0.4;
                input[index + 2] = 0.6;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    var output: [147]f32 = [9.0] ** 147;
    assert(moire.apply(input[0..], 7, 7, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    const center: usize = (3 * 7 + 3) * 3;
    assert(output[center] > input[center]);
    assert(output[center + 2] < input[center + 2]);
    assert(output[center] - input[center] <= 0.101);

    var neutral: [147]f32 = [0.2] ** 147;
    neutral[center] = 0.8;
    neutral[center + 1] = 0.8;
    neutral[center + 2] = 0.8;
    assert(moire.apply(neutral[0..], 7, 7, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[center] == neutral[center]);
}

test "moire rejects invalid CFA shape nonfinite and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings();
    bad.cfa = [0, 1, 2, 1];
    assert(moire.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 1);
    assert(moire.apply(input[0..], 2, 1, settings(), output[0..], no_cancel, 0) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    assert(moire.apply(nonfinite[0..], 1, 1, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(moire.apply(input[0..], 1, 1, settings(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[2] == 9.0);
}
