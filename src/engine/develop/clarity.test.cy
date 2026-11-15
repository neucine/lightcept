import .engine.core.core;
import .engine.develop.clarity;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): clarity.ClarityAsset {
    return {
        version: 1,
        amount: 1.0,
        edge_scale_y: 0.5,
        noise_threshold_y: 0.0,
        maximum_offset_y: 0.05
    };
}

test "clarity preserves a constant scene and disabled values" {
    const uniform: [9]f32 = [0.2] ** 9;
    var output: [9]f32 = [9.0] ** 9;
    assert(clarity.apply(uniform[0..], 3, 1, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == uniform[0] and output[8] == uniform[8]);
    var disabled = settings();
    disabled.amount = 0.0;
    const varied: [6]f32 = [-0.2, 0.1, 1.2, 0.2, 0.3, 0.4];
    var unchanged: [6]f32 = [9.0] ** 6;
    assert(clarity.apply(varied[0..], 2, 1, disabled,
        unchanged[0..], no_cancel, 0
    ) == 0);
    assert(unchanged[0] == varied[0] and unchanged[2] == varied[2]);
}

test "clarity boosts midscale luminance and caps scene change" {
    var input: [33]f32 = [0.2] ** 33;
    var pixel: usize = 4;
    while pixel <= 6 {
        input[pixel * 3] = 0.4;
        input[pixel * 3 + 1] = 0.4;
        input[pixel * 3 + 2] = 0.4;
        pixel = pixel + 1;
    }
    var output: [33]f32 = [9.0] ** 33;
    assert(clarity.apply(input[0..], 11, 1, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[5 * 3] > input[5 * 3]);
    assert(output[5 * 3] <= 0.451);
    assert(output[0] <= input[0] and output[0] >= 0.149);
    assert(output[5 * 3] - output[5 * 3 + 1] == 0.0);
}

test "clarity rounds fractional scene output" {
    var input: [33]f32 = [0.123] ** 33;
    var pixel: usize = 4;
    while pixel <= 6 {
        input[pixel * 3] = 0.437;
        input[pixel * 3 + 1] = 0.437;
        input[pixel * 3 + 2] = 0.437;
        pixel = pixel + 1;
    }
    var output: [33]f32 = [9.0] ** 33;
    assert(clarity.apply(input[0..], 11, 1, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[5 * 3] != 9.0);
    assert(output[5 * 3] > 0.38 and output[5 * 3] < 0.49);
}

test "clarity rejects invalid settings shape nonfinite and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings();
    bad.edge_scale_y = 0.0;
    assert(clarity.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 1);
    assert(clarity.apply(input[0..], 2, 1, settings(), output[0..], no_cancel, 0) == 2);
    const infinity = core.positive_infinity32();
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    assert(clarity.apply(nonfinite[0..], 1, 1, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(clarity.apply(input[0..], 1, 1, settings(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[2] == 9.0);
}
