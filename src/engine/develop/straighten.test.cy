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

test "full resolution straighten samples f64 working RGB" {
    const input: [27]f64 = [
        0.0, 0.0, 0.5, 1.0, 0.0, 0.5, 2.0, 0.0, 0.5,
        0.0, 1.0, 0.5, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5,
        0.0, 2.0, 0.5, 1.0, 2.0, 0.5, 2.0, 2.0, 0.5
    ];
    var output: [27]f64 = [9.0] ** 27;
    assert(straighten.apply_f64(input[0..], 3, 3, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 0.0 and output[1] == 0.0);
    assert(output[3] > 0.8 and output[3] < 0.81);
    assert(output[12] == 1.0 and output[13] == 1.0);
    var neutral = settings();
    neutral.angle_radians = 0.0;
    assert(straighten.apply_f64(input[0..], 3, 3, neutral,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[26] == input[26]);
}

test "straighten region exactly selects full rotated f64 pixels" {
    const input: [75]f64 = [
        0.0, 0.0, 0.5, 1.0, 0.0, 0.5, 2.0, 0.0, 0.5, 3.0, 0.0, 0.5, 4.0, 0.0, 0.5,
        0.0, 1.0, 0.5, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5, 3.0, 1.0, 0.5, 4.0, 1.0, 0.5,
        0.0, 2.0, 0.5, 1.0, 2.0, 0.5, 2.0, 2.0, 0.5, 3.0, 2.0, 0.5, 4.0, 2.0, 0.5,
        0.0, 3.0, 0.5, 1.0, 3.0, 0.5, 2.0, 3.0, 0.5, 3.0, 3.0, 0.5, 4.0, 3.0, 0.5,
        0.0, 4.0, 0.5, 1.0, 4.0, 0.5, 2.0, 4.0, 0.5, 3.0, 4.0, 0.5, 4.0, 4.0, 0.5
    ];
    var full: [75]f64 = [9.0] ** 75;
    var region: [18]f64 = [9.0] ** 18;
    assert(straighten.apply_f64(input[0..], 5, 5, settings(),
        full[0..], no_cancel, 0
    ) == 0);
    assert(straighten.apply_region_f64(input[0..], 5, 5, settings(),
        3, 1, 2, 3, region[0..], no_cancel, 0
    ) == 0);
    var row: usize = 0;
    while row < 3 {
        var channel: usize = 0;
        while channel < 6 {
            assert(region[row * 6 + channel] == full[((row + 1) * 5 + 3) * 3 + channel]);
            channel = channel + 1;
        }
        row = row + 1;
    }
    assert(straighten.apply_region_f64(input[0..], 5, 5, settings(),
        4, 4, 2, 2, region[0..], no_cancel, 0
    ) == 2);
}

test "straighten windowed region matches full rotated pixels" {
    var input: [147]f64 = [0.0] ** 147;
    var pixel: usize = 0;
    while pixel < 49 {
        input[pixel * 3] = (pixel % 7) as f64;
        input[pixel * 3 + 1] = (pixel / 7) as f64;
        input[pixel * 3 + 2] = 0.5;
        pixel = pixel + 1;
    }
    var full: [147]f64 = [9.0] ** 147;
    assert(straighten.apply_f64(input[0..], 7, 7, settings(),
        full[0..], no_cancel, 0
    ) == 0);
    const window = straighten.source_window(7, 7, settings(), 4, 1, 3, 4);
    assert(window.status == 0 and window.width * window.height < 49);
    var source: [147]f64 = [0.0] ** 147;
    var row: usize = 0;
    while row < window.height {
        var column: usize = 0;
        while column < window.width * 3 {
            source[row * window.width * 3 + column] =
            input[((window.top + row) * 7 + window.left) * 3 + column];
            column = column + 1;
        }
        row = row + 1;
    }
    var result: [36]f64 = [9.0] ** 36;
    assert(straighten.apply_window_region_f64(
        source[0..window.width * window.height * 3], 7, 7, settings(),
        window, 4, 1, 3, 4, result[0..], no_cancel, 0
    ) == 0);
    row = 0;
    while row < 4 {
        var channel: usize = 0;
        while channel < 9 {
            assert(result[row * 9 + channel] ==
                full[((row + 1) * 7 + 4) * 3 + channel]
            );
            channel = channel + 1;
        }
        row = row + 1;
    }
}
