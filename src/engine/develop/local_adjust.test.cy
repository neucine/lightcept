import .engine.core.core;
import .engine.develop.local_adjust;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "local composite preserves zero coverage and extrapolates 200 percent" {
    const base: [6]f32 = [0.2, 0.4, -0.1, 0.2, 0.4, -0.1];
    const edited: [6]f32 = [0.4, 0.5, 0.0, 0.4, 0.5, 0.0];
    const mask: [2]f32 = [0.0, 1.0];
    var output: [6]f32 = [9.0, 9.0, 9.0, 9.0, 9.0, 9.0];
    assert(local_adjust.composite(base[0..], edited[0..], mask[0..], 2, 1,
        200, output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == base[0] and output[1] == base[1] and output[2] == base[2]);
    assert(output[3] > 0.599999 and output[3] < 0.600001);
    assert(output[4] > 0.599999 and output[4] < 0.600001);
    assert(output[5] > 0.099999 and output[5] < 0.100001);
}

test "local composite uses fractional mask and percent independently" {
    assert(local_adjust.mix(0.2, 0.6, 0.5, 100) > 0.399999);
    assert(local_adjust.mix(0.2, 0.6, 0.5, 100) < 0.400001);
    assert(local_adjust.mix(0.2, 0.6, 0.5, 50) > 0.299999);
    assert(local_adjust.mix(0.2, 0.6, 0.5, 50) < 0.300001);
}

test "local composite rounds ordinary fractional image values" {
    const base: [3]f32 = [0.07, 0.23, 0.41];
    const edited: [3]f32 = [0.19, 0.57, 0.73];
    const mask: [1]f32 = [0.37];
    var output: [3]f32 = [9.0] ** 3;
    assert(local_adjust.composite(base[0..], edited[0..], mask[0..],
        1, 1, 67, output[0..], no_cancel, 0
    ) == 0);
    const expected = local_adjust.mix(base[0] as f64, edited[0] as f64,
        mask[0] as f64, 67
    );
    assert((output[0] as f64) > expected - 0.000001
        and (output[0] as f64) < expected + 0.000001
    );
}

test "local composite rejects failures before writing and cancellation" {
    const base: [3]f32 = [0.2, 0.3, 0.4];
    const edited: [3]f32 = [0.3, 0.4, 0.5];
    const mask: [1]f32 = [1.0];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    assert(local_adjust.composite(base[0..], edited[0..], mask[0..], 1, 1,
        201, output[0..], no_cancel, 0
    ) == 1);
    assert(local_adjust.composite(base[0..], edited[0..], mask[0..], 2, 1,
        100, output[0..], no_cancel, 0
    ) == 2);
    const invalid_mask: [1]f32 = [1.1];
    assert(local_adjust.composite(base[0..], edited[0..], invalid_mask[0..], 1, 1,
        100, output[0..], no_cancel, 0
    ) == 3);
    const infinity = core.positive_infinity32();
    const invalid_edited: [3]f32 = [infinity, 0.4, 0.5];
    assert(local_adjust.composite(base[0..], invalid_edited[0..], mask[0..], 1, 1,
        100, output[0..], no_cancel, 0
    ) == 3);
    const large_base: [3]f32 = [-300000000000000000000000000000000000000.0, 0.0, 0.0];
    const large_edit: [3]f32 = [300000000000000000000000000000000000000.0, 0.0, 0.0];
    assert(local_adjust.composite(large_base[0..], large_edit[0..], mask[0..], 1, 1,
        200, output[0..], no_cancel, 0
    ) == 4);
    assert(local_adjust.composite(base[0..], edited[0..], mask[0..], 1, 1,
        100, output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[1] == 9.0 and output[2] == 9.0);
}
