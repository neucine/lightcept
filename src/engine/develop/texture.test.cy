import .engine.develop.texture;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): texture.TextureAsset {
    return {
        version: 1,
        edge_limit_y: 0.3,
        amount: 1.0,
        noise_threshold_y: 0.001,
        maximum_offset_y: 0.02
    };
}

test "texture retains neutral and disabled images" {
    const uniform: [9]f32 = [0.2] ** 9;
    var output: [9]f32 = [9.0] ** 9;
    assert(texture.apply(uniform[0..], 3, 1, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == uniform[0] and output[8] == uniform[8]);
    var disabled = settings();
    disabled.amount = 0.0;
    const varied: [6]f32 = [-0.2, 0.1, 1.2, 0.2, 0.3, 0.4];
    var unchanged: [6]f32 = [9.0] ** 6;
    assert(texture.apply(varied[0..], 2, 1, disabled,
        unchanged[0..], no_cancel, 0
    ) == 0);
    assert(unchanged[0] == varied[0] and unchanged[2] == varied[2]);
}

test "texture boosts small detail and leaves a strong edge alone" {
    var input: [27]f32 = [0.2] ** 27;
    input[3] = 0.24;
    input[4] = 0.24;
    input[5] = 0.24;
    var pixel: usize = 5;
    while pixel < 9 {
        input[pixel * 3] = 1.0;
        input[pixel * 3 + 1] = 1.0;
        input[pixel * 3 + 2] = 1.0;
        pixel = pixel + 1;
    }
    var output: [27]f32 = [9.0] ** 27;
    assert(texture.apply(input[0..], 9, 1, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[3] > input[3] and output[3] <= 0.261);
    assert(output[4 * 3] == input[4 * 3]);
    assert(output[5 * 3] == input[5 * 3]);
}

test "texture rejects invalid input and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings();
    bad.edge_limit_y = 0.0;
    assert(texture.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 1);
    assert(texture.apply(input[0..], 2, 1, settings(), output[0..], no_cancel, 0) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    assert(texture.apply(nonfinite[0..], 1, 1, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(texture.apply(input[0..], 1, 1, settings(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[2] == 9.0);
}
