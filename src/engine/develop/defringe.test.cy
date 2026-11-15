import .engine.core.core;
import .engine.develop.defringe;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): defringe.DefringeAsset {
    return {
        version: 1,
        cfa: [0, 1, 1, 2],
        chroma_threshold: 0.05,
        edge_threshold_y: 0.1,
        strength: 1.0,
        maximum_change: 0.1
    };
}

test "defringe preserves constant color and disabled input" {
    const uniform: [27]f32 = [0.3] ** 27;
    var output: [27]f32 = [9.0] ** 27;
    assert(defringe.apply(uniform[0..], 3, 3, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == uniform[0] and output[26] == uniform[26]);
    var disabled = settings();
    disabled.strength = 0.0;
    const varied: [3]f32 = [-0.1, 0.3, 1.5];
    var unchanged: [3]f32 = [9.0] ** 3;
    assert(defringe.apply(varied[0..], 1, 1, disabled,
        unchanged[0..], no_cancel, 0
    ) == 0);
    assert(unchanged[0] == varied[0] and unchanged[2] == varied[2]);
}

test "defringe attenuates isolated false chroma at luminance edge" {
    var input: [75]f32 = [0.2] ** 75;
    var pixel: usize = 0;
    while pixel < 25 {
        if pixel % 5 >= 2 {
            input[pixel * 3] = 0.8;
            input[pixel * 3 + 1] = 0.8;
            input[pixel * 3 + 2] = 0.8;
        }
        pixel = pixel + 1;
    }
    const index: usize = (2 * 5 + 2) * 3;
    input[index] = 1.2;
    input[index + 1] = 0.4;
    input[index + 2] = 1.2;
    var output: [75]f32 = [9.0] ** 75;
    assert(defringe.apply(input[0..], 5, 5, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[index] < input[index] and output[index + 1] > input[index + 1]);
    assert(output[index] >= 1.099 and output[index + 1] <= 0.501);
    assert(output[0] == input[0]);
}

test "defringe rejects invalid CFA shape nonfinite and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings();
    bad.cfa = [0, 1, 2, 1];
    assert(defringe.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 1);
    assert(defringe.apply(input[0..], 2, 1, settings(), output[0..], no_cancel, 0) == 2);
    const infinity = core.positive_infinity32();
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    assert(defringe.apply(nonfinite[0..], 1, 1, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(defringe.apply(input[0..], 1, 1, settings(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[2] == 9.0);
}
