import .engine.color.working_to_linear_srgb;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "working to linear sRGB retains out-of-gamut primary evidence" {
    const input: [6]f32 = [1.0, 0.0, 0.0, 0.25, 0.25, 0.25];
    var output: [6]f32 = [9.0] ** 6;
    assert(working_to_linear_srgb.apply(input[0..], 2, 1,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > 1.66 and output[0] < 1.661);
    assert(output[1] < -0.124 and output[2] < -0.018);
    assert(output[3] > 0.24999 and output[3] < 0.25001);
    assert(output[4] > 0.24999 and output[4] < 0.25001);
    assert(output[5] > 0.24999 and output[5] < 0.25001);
}

test "standalone matrix matches existing fixed output conversion" {
    const converted = working_to_linear_srgb.convert(0.4, 0.2, 0.1);
    assert(converted[0] == output_color.rec2020_to_linear_srgb_channel(
        0.4, 0.2, 0.1, 0
    ));
    assert(converted[1] == output_color.rec2020_to_linear_srgb_channel(
        0.4, 0.2, 0.1, 1
    ));
    assert(converted[2] == output_color.rec2020_to_linear_srgb_channel(
        0.4, 0.2, 0.1, 2
    ));
}

test "working conversion validates shape input and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0] ** 3;
    assert(working_to_linear_srgb.apply(input[0..], 2, 1,
        output[0..], no_cancel, 0
    ) == 1);
    const invalid: [3]f32 = [9.0, 0.3, 0.4];
    assert(working_to_linear_srgb.apply(invalid[0..], 1, 1,
        output[0..], no_cancel, 0
    ) == 2);
    assert(working_to_linear_srgb.apply(input[0..], 1, 1,
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
