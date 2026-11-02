import .engine.develop.brush;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "brush capsule has round caps and exact interior" {
    const points: [:]brush.Point = [{
        x: 1.5,
        y: 0.5
    }, {
        x: 3.5,
        y: 0.5
    }];
    const strokes: [:]brush.Stroke = [{
        first: 0,
        count: 2,
        radius_pixels: 1.0,
        inner_fraction: 0.5
    }];
    const asset: brush.BrushAsset = {
        version: 1,
        points: points,
        strokes: strokes
    };
    assert(brush.valid(&asset, 5, 1));
    assert(brush.coverage(&asset, 2.5, 0.5) == 1.0);
    assert(brush.coverage(&asset, 0.5, 0.5) == 0.0);
    assert(brush.coverage(&asset, 1.5, 1.25) > 0.499999
        and brush.coverage(&asset, 1.5, 1.25) < 0.500001
    );
    var output: [5]f32 = [9.0, 9.0, 9.0, 9.0, 9.0];
    assert(brush.build(5, 1, &asset, output[0..], no_cancel, 0) == 0);
    assert(output[0] == 0.0 and output[1] == 1.0 and output[2] == 1.0
        and output[3] == 1.0 and output[4] == 0.0
    );
}

test "brush stroke history unions separate marks" {
    const points: [:]brush.Point = [{
        x: 0.5,
        y: 0.5
    }, {
        x: 4.5,
        y: 0.5
    }];
    const strokes: [:]brush.Stroke = [{
            first: 0,
            count: 1,
            radius_pixels: 0.5,
            inner_fraction: 0.0
        }, {
            first: 1,
            count: 1,
            radius_pixels: 0.5,
            inner_fraction: 0.0
        }
    ];
    const asset: brush.BrushAsset = {
        version: 1,
        points: points,
        strokes: strokes
    };
    var output: [5]f32 = [9.0, 9.0, 9.0, 9.0, 9.0];
    assert(brush.build(5, 1, &asset, output[0..], no_cancel, 0) == 0);
    assert(output[0] == 1.0 and output[1] == 0.0 and output[2] == 0.0
        and output[3] == 0.0 and output[4] == 1.0
    );
}

test "brush rounds fractional feather coverage" {
    const points: [:]brush.Point = [{
        x: 1.1,
        y: 0.5
    }];
    const strokes: [:]brush.Stroke = [{
        first: 0,
        count: 1,
        radius_pixels: 1.0,
        inner_fraction: 0.0
    }];
    const asset: brush.BrushAsset = {
        version: 1,
        points: points,
        strokes: strokes
    };
    var output: [3]f32 = [9.0] ** 3;
    assert(brush.build(3, 1, &asset, output[0..], no_cancel, 0) == 0);
    const expected = brush.coverage(&asset, 0.5, 0.5);
    assert((output[0] as f64) > expected - 0.000001
        and (output[0] as f64) < expected + 0.000001
    );
    assert(output[0] > 0.0 and output[0] < 1.0);
}

test "brush validates stroke ranges and cancellation" {
    const points: [:]brush.Point = [{
        x: 0.5,
        y: 0.5
    }];
    const invalid_strokes: [:]brush.Stroke = [{
        first: 1,
        count: 1,
        radius_pixels: 0.5,
        inner_fraction: 0.0
    }];
    const invalid: brush.BrushAsset = {
        version: 1,
        points: points,
        strokes: invalid_strokes
    };
    var output: [1]f32 = [9.0];
    assert(brush.build(1, 1, &invalid, output[0..], no_cancel, 0) == 1);
    const strokes: [:]brush.Stroke = [{
        first: 0,
        count: 1,
        radius_pixels: 0.5,
        inner_fraction: 0.0
    }];
    const points2: [:]brush.Point = [{
        x: 0.5,
        y: 0.5
    }];
    const valid: brush.BrushAsset = {
        version: 1,
        points: points2,
        strokes: strokes
    };
    assert(not brush.valid(&valid, 0, 1));
    assert(not brush.valid(&valid, 1, 0));
    assert(not brush.valid(&valid, brush.maximum_pixels + 1, 1));
    assert(brush.build(2, 1, &valid, output[0..], no_cancel, 0) == 2);
    assert(brush.build(1, 1, &valid, output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0);
}
