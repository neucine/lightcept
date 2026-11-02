import .engine.develop.linear_gradient;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "linear gradient projects pixel centers on a photographic strip" {
    const asset: linear_gradient.GradientAsset = {
        version: 1,
        start_x: 0.16666666666666666,
        start_y: 0.5,
        end_x: 0.8333333333333334,
        end_y: 0.5
    };
    var output: [3]f32 = [9.0, 9.0, 9.0];
    assert(linear_gradient.build(3, 1, asset, output[0..], no_cancel, 0) == 0);
    assert(output[0] < 0.000001 and output[0] >= 0.0);
    assert(output[1] > 0.499999 and output[1] < 0.500001);
    assert(output[2] > 0.999999 and output[2] <= 1.0);
}

test "diagonal gradient and clamping are analytical" {
    const asset: linear_gradient.GradientAsset = {
        version: 1,
        start_x: 0.0,
        start_y: 0.0,
        end_x: 1.0,
        end_y: 1.0
    };
    assert(linear_gradient.coverage(asset, 0.5, 0.5) == 0.5);
    assert(linear_gradient.coverage(asset, -1.0, -1.0) == 0.0);
    assert(linear_gradient.coverage(asset, 2.0, 2.0) == 1.0);
}

test "gradient rounds fractional seven-pixel coverage" {
    const asset: linear_gradient.GradientAsset = {
        version: 1,
        start_x: 0.0,
        start_y: 0.5,
        end_x: 1.0,
        end_y: 0.5
    };
    var output: [7]f32 = [9.0] ** 7;
    assert(linear_gradient.build(7, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > 1.0 / 14.0 - 0.000001
        and (output[0] as f64) < 1.0 / 14.0 + 0.000001
    );
    assert(output[3] == 0.5);
}

test "linear gradient rejects invalid geometry and cancellation" {
    const invalid: linear_gradient.GradientAsset = {
        version: 1,
        start_x: 0.5,
        start_y: 0.5,
        end_x: 0.5,
        end_y: 0.5
    };
    const valid: linear_gradient.GradientAsset = {
        version: 1,
        start_x: 0.0,
        start_y: 0.5,
        end_x: 1.0,
        end_y: 0.5
    };
    var output: [2]f32 = [9.0, 9.0];
    assert(linear_gradient.build(2, 1, invalid, output[0..], no_cancel, 0) == 1);
    var too_short = valid;
    too_short.end_x = 0.0000005;
    too_short.start_y = 0.5;
    too_short.end_y = 0.5;
    assert(not linear_gradient.valid(too_short));
    assert(linear_gradient.build(3, 1, valid, output[0..], no_cancel, 0) == 2);
    assert(linear_gradient.build(2, 1, valid, output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[1] == 9.0);
}
