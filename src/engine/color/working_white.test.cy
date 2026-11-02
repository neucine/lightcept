import .engine.color.working_white;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "working white preserves neutral scene RGB and applies bounded gains" {
    const input: [9]f32 = [-0.25, 0.18, 8.0, 0.1, 0.2, 0.3, 1.0, 1.0, 1.0];
    var output: [9]f32 = [9.0] ** 9;
    assert(working_white.apply(input[0..], 3, 1, working_white.neutral(),
        output[0..], no_cancel, 0
    ) == 0);
    var index: usize = 0;
    while index < 9 {
        assert(output[index] == input[index]);
        index = index + 1;
    }
    const gains: working_white.WorkingGains = {
        version: 1,
        red: 2.0,
        green: 1.0,
        blue: 0.5
    };
    assert(working_white.apply(input[0..], 3, 1, gains,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == -0.5 and output[1] == input[1] and output[2] == 4.0);
    assert(output[6] == 2.0 and output[7] == 1.0 and output[8] == 0.5);
    const fractional: working_white.WorkingGains = {
        version: 1,
        red: 1.25,
        green: 0.75,
        blue: 8.0
    };
    assert(working_white.apply(input[0..], 3, 1, fractional,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == -0.3125 and output[2] == 64.0);
    assert(output[3] > 0.124999 and output[3] < 0.125001);
}

test "working white rejects invalid gains input shape and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    var gains = working_white.neutral();
    gains.red = 0.0;
    assert(working_white.apply(input[0..], 1, 1, gains, output[0..], no_cancel, 0) == 1);
    assert(working_white.apply(input[0..], 0, 1, working_white.neutral(), output[0..], no_cancel, 0) == 2);
    const bad: [3]f32 = [9.0, 0.3, 0.4];
    assert(working_white.apply(bad[0..], 1, 1, working_white.neutral(), output[0..], no_cancel, 0) == 3);
    assert(working_white.apply(input[0..], 1, 1, working_white.neutral(), output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0);
}
