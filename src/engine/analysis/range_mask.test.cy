import .engine.analysis.range_mask;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "range mask has exact plateau and smooth symmetric shoulders" {
    const asset: range_mask.RangeAsset = {
        version: 1,
        outer_low: 0.0,
        inner_low: 0.2,
        inner_high: 0.8,
        outer_high: 1.0
    };
    assert(range_mask.valid(asset));
    assert(range_mask.coverage(asset, -0.1) == 0.0);
    assert(range_mask.coverage(asset, 0.1) > 0.499999
        and range_mask.coverage(asset, 0.1) < 0.500001
    );
    assert(range_mask.coverage(asset, 0.5) == 1.0);
    assert(range_mask.coverage(asset, 0.9) > 0.499999
        and range_mask.coverage(asset, 0.9) < 0.500001
    );
    assert(range_mask.coverage(asset, 1.5) == 0.0);
}

test "range mask measures a small neutral and colored image" {
    const asset: range_mask.RangeAsset = {
        version: 1,
        outer_low: 0.0,
        inner_low: 0.2,
        inner_high: 0.8,
        outer_high: 1.0
    };
    const input: [12]f32 = [0.1, 0.1, 0.1, 0.5, 0.5, 0.5,
        0.9, 0.9, 0.9, 1.2, 0.3, 0.1
    ];
    var output: [4]f32 = [9.0, 9.0, 9.0, 9.0];
    assert(range_mask.build(input[0..], 2, 2, asset, output[0..], no_cancel, 0) == 0);
    assert(output[0] > 0.499999 and output[0] < 0.500001);
    assert(output[1] == 1.0);
    assert(output[2] > 0.499999 and output[2] < 0.500001);
    assert(output[3] == 1.0);
}

test "range mask rounds a non-binary feather sample" {
    const asset: range_mask.RangeAsset = {
        version: 1,
        outer_low: 0.0,
        inner_low: 0.2,
        inner_high: 0.8,
        outer_high: 1.0
    };
    const input: [3]f32 = [0.07, 0.07, 0.07];
    var output: [1]f32 = [9.0];
    assert(range_mask.build(input[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    const expected = range_mask.coverage(asset, input[0] as f64);
    assert((output[0] as f64) > expected - 0.000001
        and (output[0] as f64) < expected + 0.000001
    );
}

test "range mask rejects malformed data without writing and polls cancellation" {
    const asset: range_mask.RangeAsset = {
        version: 1,
        outer_low: 0.0,
        inner_low: 0.2,
        inner_high: 0.8,
        outer_high: 1.0
    };
    const invalid: range_mask.RangeAsset = {
        version: 1,
        outer_low: 0.2,
        inner_low: 0.2,
        inner_high: 0.8,
        outer_high: 1.0
    };
    const input: [6]f32 = [0.1, 0.1, 0.1, 0.5, 0.5, 0.5];
    var output: [2]f32 = [9.0, 9.0];
    assert(range_mask.build(input[0..], 2, 1, invalid, output[0..], no_cancel, 0) == 1);
    assert(range_mask.build(input[0..], 3, 1, asset, output[0..], no_cancel, 0) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [6]f32 = [0.1, 0.1, 0.1, infinity, 0.5, 0.5];
    assert(range_mask.build(nonfinite[0..], 2, 1, asset, output[0..], no_cancel, 0) == 3);
    const out_of_range: [6]f32 = [0.1, 0.1, 0.1, 8.1, 0.5, 0.5];
    assert(range_mask.build(out_of_range[0..], 2, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(range_mask.build(input[0..], 2, 1, asset, output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[1] == 9.0);
}
