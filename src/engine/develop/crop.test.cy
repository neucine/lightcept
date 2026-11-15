import .engine.core.core;
import .engine.develop.crop;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn center(): crop.CropRect {
    return {
        version: 1,
        left: 1,
        top: 1,
        width: 2,
        height: 2
    };
}

test "crop selects exact scene-linear pixels and maps source coordinates" {
    const input: [36]f32 = [
        0.0, 0.1, 0.2, 1.0, 1.1, 1.2, 2.0, 2.1, 2.2, 3.0, 3.1, 3.2,
        4.0, 4.1, 4.2, 5.0, 5.1, 5.2, 6.0, 6.1, 6.2, 7.0, 7.1, 7.2,
        8.0, 8.1, 8.2, 9.0, 9.1, 9.2, 10.0, 10.1, 10.2, 11.0, 11.1, 11.2
    ];
    var output: [12]f32 = [99.0] ** 12;
    assert(crop.apply(input[0..], 4, 3, center(), output[0..], no_cancel, 0) == 0);
    assert(output[0] == 5.0 and output[3] == 6.0);
    assert(output[6] == 9.0 and output[9] == 10.0);
    assert(output[11] == input[32]);
    const inside = crop.map_source_point(center(), 4, 3, 2.0, 1.0);
    assert(inside.inside and inside.x == 1.0 and inside.y == 0.0);
    const fractional = crop.map_source_point(center(), 4, 3, 1.25, 1.75);
    assert(fractional.inside and fractional.x == 0.25
        and fractional.y == 0.75
    );
    const right_edge = crop.map_source_point(center(), 4, 3, 3.0, 1.0);
    assert(not right_edge.inside);
    const outside = crop.map_source_point(center(), 4, 3, 0.0, 1.0);
    assert(not outside.inside);
}

test "crop rejects invalid extent input shape and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0] ** 3;
    var bad: crop.CropRect = {
        version: 1,
        left: 1,
        top: 0,
        width: 1,
        height: 1
    };
    assert(crop.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 1);
    bad.left = 0;
    assert(crop.apply(input[0..], 1, 1, bad, output[0..], no_cancel, 0) == 0);
    assert(crop.apply(input[0..], 2, 1, bad, output[0..], no_cancel, 0) == 2);
    const infinity = core.positive_infinity32();
    const nonfinite: [3]f32 = [infinity, 0.2, 0.3];
    output[0] = 9.0;
    assert(crop.apply(nonfinite[0..], 1, 1, bad, output[0..], no_cancel, 0) == 3);
    assert(crop.apply(input[0..], 1, 1, bad, output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0);
}

test "full resolution crop copies f64 working RGB without quantization" {
    const input: [18]f64 = [
        -0.25, 0.5, 8.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0,
        7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0
    ];
    var output: [6]f64 = [99.0] ** 6;
    const rect: crop.CropRect = {
        version: 1,
        left: 1,
        top: 0,
        width: 1,
        height: 2
    };
    assert(crop.apply_f64(input[0..], 3, 2, rect,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 1.0 and output[1] == 2.0 and output[2] == 3.0);
    assert(output[3] == 10.0 and output[4] == 11.0 and output[5] == 12.0);
    assert(crop.apply_f64(input[0..], 3, 2, rect,
        output[0..], cancel, 0
    ) == 7);
}
