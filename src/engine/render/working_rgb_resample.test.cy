import .engine.render.working_rgb_resample;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    const ignored = context;
    return true;
}

test "working RGB area reduction preserves channel averages and identity" {
    const input: [24]f64 = [
        0.0, 10.0, 100.0, 1.0, 11.0, 101.0, 2.0, 12.0, 102.0, 3.0, 13.0, 103.0,
        4.0, 14.0, 104.0, 5.0, 15.0, 105.0, 6.0, 16.0, 106.0, 7.0, 17.0, 107.0
    ];
    var output: [6]f64 = [0.0] ** 6;
    assert(working_rgb_resample.reduce(input[0..], 4, 2, output[0..], 2, 1,
        no_cancel, 0
    ) == 0);
    assert(output[0] == 2.5 and output[1] == 12.5 and output[2] == 102.5);
    assert(output[3] == 4.5 and output[4] == 14.5 and output[5] == 104.5);
    var identity: [24]f64 = [0.0] ** 24;
    assert(working_rgb_resample.reduce(input[0..], 4, 2, identity[0..], 4, 2,
        no_cancel, 0
    ) == 0);
    assert(identity[0] == input[0] and identity[23] == input[23]);
    assert(working_rgb_resample.reduce(input[0..], 4, 2, identity[0..], 4, 2,
        cancel, 0
    ) == 7);
}
