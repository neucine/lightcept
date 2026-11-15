import .engine.core.core;
import .engine.develop.tca;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): tca.TcaAsset {
    return {
        version: 1,
        model_hash: 1,
        cfa: [0, 1, 1, 2],
        center_x_fraction: 0.5,
        center_y_fraction: 0.5,
        red_k1: 0.2,
        blue_k1: -0.2,
        maximum_change: 0.1,
        boundary_fill: [0.0, 0.0, 0.0]
    };
}

test "TCA retains CFA phase and moves red and blue independently" {
    var input: [49]f32 = [0.0] ** 49;
    var y: usize = 0;
    while y < 7 {
        var x: usize = 0;
        while x < 7 {
            const index = y * 7 + x;
            if (x + y) % 2 == 1 {
                input[index] = 0.3;
            } else if x % 2 == 0 {
                input[index] = (x as f32) * 0.1;
            } else {
                input[index] = 0.2;
                input[index] = input[index] + (x as f32) * 0.1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    var output: [49]f32 = [9.0] ** 49;
    assert(tca.apply(input[0..], 7, 7, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    const red: usize = 2 * 7 + 4;
    assert(output[red] > 0.401 and output[red] < 0.404);
    const green: usize = 2 * 7 + 3;
    assert(output[green] == input[green]);
    const blue: usize = 3 * 7 + 5;
    assert(output[blue] < input[blue] and output[blue] > 0.68);
    const red_point = tca.source_point(7, 7, settings(), 4, 2);
    assert(red_point.inside and red_point.x > 4.0);
}

test "TCA preserves disabled sites and uses explicit edge fill" {
    const input: [9]f32 = [0.4, 0.3, 0.2, 0.3, 0.4, 0.3, 0.2, 0.3, 0.4];
    var output: [9]f32 = [9.0] ** 9;
    var neutral = settings();
    neutral.red_k1 = 0.0;
    neutral.blue_k1 = 0.0;
    assert(tca.apply(input[0..], 3, 3, neutral,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[8] == input[8]);
    assert(tca.apply(input[0..], 3, 3, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 0.0);
    assert(output[1] == input[1]);
}

test "TCA rejects invalid CFA shape input and cancellation" {
    const input: [4]f32 = [0.1, 0.2, 0.3, 0.4];
    var output: [4]f32 = [9.0] ** 4;
    var bad = settings();
    bad.cfa = [0, 1, 2, 1];
    assert(tca.apply(input[0..], 2, 2, bad, output[0..], no_cancel, 0) == 1);
    assert(tca.apply(input[0..], 3, 2, settings(), output[0..], no_cancel, 0) == 2);
    const infinity = core.positive_infinity32();
    const nonfinite: [4]f32 = [infinity, 0.2, 0.3, 0.4];
    assert(tca.apply(nonfinite[0..], 2, 2, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(tca.apply(input[0..], 2, 2, settings(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[3] == 9.0);
}
