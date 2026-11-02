import .engine.analysis.sharpness_estimate;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "constant photographic patch has zero Laplacian variance" {
    const input: [75]f32 = [0.18] ** 75;
    const result = sharpness_estimate.measure(input[0..], 5, 5, 1, no_cancel, 0);
    assert(result.status == 0 and result.samples == 9 and result.variance == 0.0);
}

test "single bright detail has analytical focus energy" {
    var input: [75]f32 = [0.0] ** 75;
    input[(2 * 5 + 2) * 3] = 1.0;
    input[(2 * 5 + 2) * 3 + 1] = 1.0;
    input[(2 * 5 + 2) * 3 + 2] = 1.0;
    const result = sharpness_estimate.measure(input[0..], 5, 5, 1, no_cancel, 0);
    assert(result.status == 0 and result.mean_laplacian > -0.000001
        and result.mean_laplacian < 0.000001
    );
    assert(result.variance > 2.222221 and result.variance < 2.222223);
}

test "sharpness estimate rejects radius shape nonfinite and cancellation" {
    const input: [27]f32 = [0.2] ** 27;
    assert(sharpness_estimate.measure(input[0..], 3, 3, 3, no_cancel, 0).status == 2);
    assert(sharpness_estimate.measure(input[0..], 4, 3, 1, no_cancel, 0).status == 1);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    var bad: [27]f32 = [0.2] ** 27;
    bad[4] = infinity;
    const invalid = sharpness_estimate.measure(bad[0..], 3, 3, 1, no_cancel, 0);
    assert(invalid.status == 3 and invalid.samples == 0);
    bad[4] = 8.1;
    assert(sharpness_estimate.measure(bad[0..], 3, 3, 1,
        no_cancel, 0
    ).status == 3);
    const stopped = sharpness_estimate.measure(input[0..], 3, 3, 1, cancel, 0);
    assert(stopped.status == 7 and stopped.samples == 0);
}
