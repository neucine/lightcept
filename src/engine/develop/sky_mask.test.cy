import .engine.develop.sky_mask;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn upright(): sky_mask.SkyPolicy {
    return {
        version: 1,
        upright: true
    };
}

test "single top blue seed is selected" {
    const input: [3]f32 = [0.1, 0.2, 0.6];
    var seen: [1]u8 = [9];
    var queue: [1]usize = [9];
    var output: [1]f32 = [9.0];
    const report = sky_mask.build(input[0..], 1, 1, upright(),
        seen[0..], queue[0..], output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.selected_pixels == 1);
    assert(output[0] == 1.0);
    assert(seen[0] == 1 and queue[0] == 0);
}

test "daylight sky selects top-connected blue and cloud pixels" {
    const input: [27]f32 = [
        0.1, 0.2, 0.6, 0.8, 0.8, 0.82, 0.1, 0.7, 0.2,
        0.1, 0.2, 0.6, 0.8, 0.8, 0.82, 0.1, 0.7, 0.2,
        0.1, 0.7, 0.2, 0.1, 0.7, 0.2, 0.1, 0.2, 0.6
    ];
    var seen: [9]u8 = [9] ** 9;
    var queue: [9]usize = [9] ** 9;
    var output: [9]f32 = [9.0] ** 9;
    const report = sky_mask.build(input[0..], 3, 3, upright(),
        seen[0..], queue[0..], output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.version == 1);
    assert(report.seed_pixels == 1 and report.selected_pixels == 4);
    assert(output[0] == 1.0 and output[1] > 0.59 and output[1] <= 0.6);
    assert(output[2] == 0.0 and output[3] == 1.0 and output[4] > 0.59);
    assert(output[8] == 0.0);
}

test "sky mask without blue top seed returns no sky and rejects failures" {
    const cloud: [6]f32 = [0.8, 0.8, 0.82, 0.8, 0.8, 0.82];
    var seen: [2]u8 = [9] ** 2;
    var queue: [2]usize = [9] ** 2;
    var output: [2]f32 = [9.0] ** 2;
    const empty = sky_mask.build(cloud[0..], 2, 1, upright(),
        seen[0..], queue[0..], output[0..], no_cancel, 0
    );
    assert(empty.status == 0 and empty.selected_pixels == 0);
    assert(output[0] == 0.0 and output[1] == 0.0);
    const invalid: [6]f32 = [9.0, 0.8, 0.82, 0.8, 0.8, 0.82];
    assert(sky_mask.build(invalid[0..], 2, 1, upright(),
        seen[0..], queue[0..], output[0..], no_cancel, 0
    ).status == 3);
    const sideways: sky_mask.SkyPolicy = {
        version: 1,
        upright: false
    };
    assert(sky_mask.build(cloud[0..], 2, 1, sideways,
        seen[0..], queue[0..], output[0..], no_cancel, 0
    ).status == 1);
    assert(sky_mask.build(cloud[0..], 2, 1, upright(),
        seen[0..], queue[0..], output[0..], cancel, 0
    ).status == 7);
}
