import .engine.develop.described_mask;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "described mask resamples a source coverage raster through geometry map" {
    const coverage: [4]f32 = [0.0, 1.0, 1.0, 0.0];
    const asset: described_mask.MaskAsset = {
        version: 1,
        source_image_id: 11,
        description_id: 12,
        producer_version: 2,
        width: 2,
        height: 2,
        coverage: coverage[0..]
    };
    const map_x: [5]f32 = [0.25, 0.75, 0.25, 0.75, 0.5];
    const map_y: [5]f32 = [0.25, 0.25, 0.75, 0.75, 0.5];
    var output: [5]f32 = [9.0] ** 5;
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        5, 1, output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 0.0 and output[1] == 1.0);
    assert(output[2] == 1.0 and output[3] == 0.0);
    assert(output[4] == 0.5);
    const outside_x: [1]f32 = [-0.5];
    const outside_y: [1]f32 = [0.5];
    var outside: [1]f32 = [9.0];
    assert(described_mask.build(&asset, outside_x[0..], outside_y[0..],
        1, 1, outside[0..], no_cancel, 0
    ) == 0);
    assert(outside[0] == 0.0);
}

test "described mask rejects asset map shape and cancellation" {
    const coverage: [4]f32 = [0.0, 1.0, 1.0, 0.0];
    var asset: described_mask.MaskAsset = {
        version: 1,
        source_image_id: 11,
        description_id: 12,
        producer_version: 2,
        width: 2,
        height: 2,
        coverage: coverage[0..]
    };
    const map_x: [1]f32 = [0.5];
    const map_y: [1]f32 = [0.5];
    var output: [1]f32 = [9.0];
    asset.description_id = 0;
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        1, 1, output[0..], no_cancel, 0
    ) == 1);
    asset.description_id = 12;
    const invalid_coverage: [4]f32 = [0.0, 1.0, 1.0, 2.0];
    asset.coverage = invalid_coverage[0..];
    assert(not described_mask.valid(&asset));
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        1, 1, output[0..], no_cancel, 0
    ) == 1);
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        1, 1, output[0..], cancel, 0
    ) == 7);
    asset.coverage = coverage[0..];
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        2, 1, output[0..], no_cancel, 0
    ) == 2);
    const bad_x: [1]f32 = [3.0];
    assert(described_mask.build(&asset, bad_x[0..], map_y[0..],
        1, 1, output[0..], no_cancel, 0
    ) == 3);
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        1, 1, output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}

test "described mask rounds an inexact bilinear coverage" {
    const coverage: [4]f32 = [0.0, 1.0, 1.0, 0.0];
    const asset: described_mask.MaskAsset = {
        version: 1,
        source_image_id: 11,
        description_id: 12,
        producer_version: 2,
        width: 2,
        height: 2,
        coverage: coverage[0..]
    };
    const map_x: [1]f32 = [0.35];
    const map_y: [1]f32 = [0.65];
    var output: [1]f32 = [9.0];
    assert(described_mask.build(&asset, map_x[0..], map_y[0..],
        1, 1, output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > 0.67999 and output[0] < 0.68001);
}
