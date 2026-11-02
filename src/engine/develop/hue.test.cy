import .engine.develop.hue;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(angle: f64): hue.HueAsset {
    return {
        version: 1,
        angle_degrees: angle
    };
}

fn luminance(red: f64, green: f64, blue: f64): f64 {
    return 0.2627 * red + 0.6780 * green + 0.0593 * blue;
}

test "hue quarter turn rotates declared U V axes and preserves luminance" {
    const input: [3]f32 = [0.5, 0.25, 0.25];
    var output: [3]f32 = [9.0] ** 3;
    assert(hue.apply(input[0..], 1, 1, settings(90.0),
        output[0..], no_cancel, 0
    ) == 0);
    const before = luminance(input[0] as f64, input[1] as f64,
        input[2] as f64
    );
    const after = luminance(output[0] as f64, output[1] as f64,
        output[2] as f64
    );
    assert(after > before - 0.000001 and after < before + 0.000001);
    assert(output[2] > output[0] and output[0] > input[1]);
    assert(output[2] > 0.49 and output[2] < 0.51);
}

test "zero angle and neutral pixels remain exact" {
    const input: [6]f32 = [-0.2, 0.4, 1.5, 0.25, 0.25, 0.25];
    var output: [6]f32 = [9.0] ** 6;
    assert(hue.apply(input[0..], 2, 1, settings(0.0),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[1] == input[1]
        and output[2] == input[2]
    );
    assert(hue.apply(input[0..], 2, 1, settings(-90.0),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[3] == 0.25 and output[4] == 0.25
        and output[5] == 0.25
    );
}

test "half-turn hue preserves luminance at both angle bounds" {
    const input: [3]f32 = [0.6, 0.3, 0.2];
    var positive: [3]f32 = [9.0] ** 3;
    var negative: [3]f32 = [9.0] ** 3;
    assert(hue.apply(input[0..], 1, 1, settings(180.0),
        positive[0..], no_cancel, 0
    ) == 0);
    assert(hue.apply(input[0..], 1, 1, settings(-180.0),
        negative[0..], no_cancel, 0
    ) == 0);
    const original_y = luminance(input[0] as f64, input[1] as f64,
        input[2] as f64
    );
    const turned_y = luminance(positive[0] as f64,
        positive[1] as f64, positive[2] as f64
    );
    assert(turned_y > original_y - 0.000001
        and turned_y < original_y + 0.000001
    );
    assert(positive[0] < input[0] and positive[2] > input[2]);
    assert(positive[0] > negative[0] - 0.000001
        and positive[0] < negative[0] + 0.000001
    );
}

test "hue rejects angle shape input and cancellation" {
    const input: [3]f32 = [0.25, 0.25, 0.25];
    var output: [3]f32 = [9.0] ** 3;
    assert(hue.apply(input[0..], 1, 1, settings(181.0),
        output[0..], no_cancel, 0
    ) == 1);
    assert(hue.apply(input[0..], 2, 1, settings(90.0),
        output[0..], no_cancel, 0
    ) == 2);
    const invalid: [3]f32 = [9.0, 0.25, 0.25];
    assert(hue.apply(invalid[0..], 1, 1, settings(90.0),
        output[0..], no_cancel, 0
    ) == 3);
    assert(hue.apply(input[0..], 1, 1, settings(90.0),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
