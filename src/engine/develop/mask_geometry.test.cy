import .engine.develop.mask_geometry;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "ellipse has full center, smooth annulus, and zero exterior" {
    const asset: mask_geometry.EllipseAsset = {
        version: 1,
        center_x: 0.5,
        center_y: 0.5,
        radius_x: 0.5,
        radius_y: 0.5,
        inner_fraction: 0.5
    };
    assert(mask_geometry.valid(asset));
    assert(mask_geometry.coverage(asset, 0.5, 0.5) == 1.0);
    assert(mask_geometry.coverage(asset, 0.75, 0.5) == 1.0);
    assert(mask_geometry.coverage(asset, 0.875, 0.5) > 0.499999
        and mask_geometry.coverage(asset, 0.875, 0.5) < 0.500001
    );
    assert(mask_geometry.coverage(asset, 1.0, 0.5) == 0.0);
    assert(mask_geometry.coverage(asset, 0.5, 1.0) == 0.0);
}

test "ellipse mask samples a small photographic frame" {
    const asset: mask_geometry.EllipseAsset = {
        version: 1,
        center_x: 0.5,
        center_y: 0.5,
        radius_x: 0.5,
        radius_y: 0.5,
        inner_fraction: 0.4
    };
    var output: [9]f32 = [9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0];
    assert(mask_geometry.build(3, 3, asset, output[0..], no_cancel, 0) == 0);
    assert(output[4] == 1.0);
    assert(output[0] > 0.0 and output[0] < output[1]);
    assert(output[0] == output[2] and output[0] == output[6]
        and output[0] == output[8]
    );
    assert(output[1] > 0.0 and output[1] < 1.0);
    assert(output[3] == output[5] and output[1] == output[7]);
    const expected_corner = mask_geometry.coverage(asset, 1.0 / 6.0, 1.0 / 6.0);
    assert((output[0] as f64) > expected_corner - 0.000001
        and (output[0] as f64) < expected_corner + 0.000001
    );
}

test "ellipse rejects bad shape and cancellation before writing" {
    const invalid: mask_geometry.EllipseAsset = {
        version: 1,
        center_x: 0.5,
        center_y: 0.5,
        radius_x: 0.0,
        radius_y: 0.5,
        inner_fraction: 0.5
    };
    const valid: mask_geometry.EllipseAsset = {
        version: 1,
        center_x: 0.5,
        center_y: 0.5,
        radius_x: 0.5,
        radius_y: 0.5,
        inner_fraction: 0.5
    };
    var output: [1]f32 = [9.0];
    assert(mask_geometry.build(1, 1, invalid, output[0..], no_cancel, 0) == 1);
    assert(mask_geometry.build(2, 1, valid, output[0..], no_cancel, 0) == 2);
    assert(mask_geometry.build(1, 1, valid, output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0);
}
