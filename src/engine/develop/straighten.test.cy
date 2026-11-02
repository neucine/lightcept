import .engine.develop.straighten;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): straighten.StraightenAsset {
    return {
        version: 1,
        angle_radians: 0.2,
        boundary_fill: [0.0, 0.0, 0.0]
    };
}

test "straighten identity and source point mapping" {
    const input: [12]f32 = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6,
        0.7, 0.8, 0.9, 1.0, 1.1, 1.2
    ];
    var output: [12]f32 = [9.0] ** 12;
    var neutral = settings();
    neutral.angle_radians = 0.0;
    assert(straighten.apply(input[0..], 2, 2, neutral,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[11] == input[11]);
    const mapped = straighten.map_source_point(3, 3, settings(), 1.0, 1.0);
    assert(mapped.inside and mapped.x == 1.0 and mapped.y == 1.0);
    const clockwise = straighten.map_source_point(5, 5, settings(), 3.0, 2.0);
    assert(clockwise.inside and clockwise.x > 2.980 and clockwise.x < 2.981);
    assert(clockwise.y > 2.198 and clockwise.y < 2.200);
    const outside = straighten.map_source_point(3, 3, settings(), 0.0, 0.0);
    assert(not outside.inside);
}

test "straighten bilinear samples a rotated gradient and fills outside" {
    const input: [27]f32 = [
        0.0, 0.0, 0.5, 1.0, 0.0, 0.5, 2.0, 0.0, 0.5,
        0.0, 1.0, 0.5, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5,
        0.0, 2.0, 0.5, 1.0, 2.0, 0.5, 2.0, 2.0, 0.5
    ];
    var output: [27]f32 = [9.0] ** 27;
    assert(straighten.apply(input[0..], 3, 3, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 0.0 and output[1] == 0.0 and output[2] == 0.0);
    assert(output[3] > 0.8 and output[3] < 0.81);
    assert(output[4] > 0.019 and output[4] < 0.021);
    assert(output[12] == 1.0 and output[13] == 1.0);
}

test "straighten rejects invalid asset shape input and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0] ** 3;
    var bad = settings();
    bad.angle_radians = 0.4;
    assert(straighten.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 1);
    assert(straighten.apply(input[0..], 2, 1, settings(),
        output[0..], no_cancel, 0
    ) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    assert(straighten.apply(nonfinite[0..], 1, 1, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(straighten.apply(input[0..], 1, 1, settings(),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[2] == 9.0);
}
