import .engine.color.srgb_transfer;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "sRGB transfer matches fixed output and its piecewise boundary" {
    const input: [6]f32 = [0.0, 0.001, 0.003, 0.004, 0.25, 1.0];
    var output: [6]f32 = [9.0] ** 6;
    assert(srgb_transfer.apply(input[0..], 2, 1,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 0.0 and output[5] == 1.0);
    assert(output[1] > 0.0129 and output[1] < 0.0130);
    assert(output[3] > 0.05 and output[3] < 0.051);
    const fixed = output_color.srgb_transfer(input[4] as f64);
    assert((output[4] as f64) > fixed - 0.000001
        and (output[4] as f64) < fixed + 0.000001
    );
}

test "sRGB transfer rejects shape domain and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0] ** 3;
    assert(srgb_transfer.apply(input[0..], 2, 1,
        output[0..], no_cancel, 0
    ) == 1);
    const invalid: [3]f32 = [-0.1, 0.3, 0.4];
    assert(srgb_transfer.apply(invalid[0..], 1, 1,
        output[0..], no_cancel, 0
    ) == 2);
    assert(srgb_transfer.apply(input[0..], 1, 1,
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
