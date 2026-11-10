import .engine.raw.camera_mosaic;
import .engine.pipeline.camera_mosaic_pipeline;
import .engine.render.mosaic_render;
import .engine.pipeline.spatial_camera_pipeline;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    return context == 7;
}

test "shared camera mosaic route preserves both fitted and baseline preview bytes" {
    const image: camera_mosaic.CameraMosaic = {
        width: 4,
        height: 4,
        cfa: [0, 1, 1, 2],
        camera_to_xyz_d50: [0.96422, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.82521],
        neutral: [1.0, 1.0, 1.0],
        baseline_exposure_ev: 0.0,
        orientation: 1,
        status: 0
    };
    var normalized: [16]f32 = [0.5] ** 16;
    var output: [64]u8 = [9] ** 64;
    var reference: [64]u8 = [9] ** 64;
    var empty_band: [0]f64 = [];
    var empty_bytes: [0]u8 = [];
    const scratch: camera_mosaic_pipeline.SpatialScratch = {
        camera: normalized[0..0],
        band: empty_band[0..],
        source_pyramid: normalized[0..0],
        rim: normalized[0..0],
        lum: normalized[0..0],
        touched: empty_bytes[0..],
        near: empty_bytes[0..]
    };
    const edit: camera_mosaic_pipeline.DevelopSettings = {
        exposure_ev: 0.5,
        contrast_percent: 0.0
    };
    var mode: u32 = camera_mosaic_pipeline.baseline_bilinear_v1;
    while mode <= camera_mosaic_pipeline.fitted_mhc_v1 {
        var expected_edit = edit;
        if mode == camera_mosaic_pipeline.baseline_bilinear_v1 {
            expected_edit.exposure_ev = 0.0;
        }
        assert(camera_mosaic_pipeline.render_rgba8(image, normalized[0..],
            output[0..], 4, 4, mode, expected_edit, scratch,
            no_cancel, 0
        ) == 0);
        assert(mosaic_render.render_oriented_bayer_preview_v8(
            normalized[0..].ptr as! *const f32, 16, 4, 4,
            image.cfa[0..].ptr as! *const u32, 4,
            image.camera_to_xyz_d50[0..].ptr as! *const f64, 9,
            reference[0..].ptr as! *u8, 64, 4, 4,
            0.0, expected_edit.exposure_ev as f64, mode as u32, 1,
            no_cancel, 0
        ) == 0);
        var index: usize = 0;
        while index < 64 {
            assert(output[index] == reference[index]);
            index = index + 1;
        }
        mode = mode + 1;
    }
    output[0] = 9;
    assert(camera_mosaic_pipeline.render_rgba8(image, normalized[0..],
        output[0..], 4, 4, 99, edit, scratch,
        no_cancel, 0
    ) == 4 and output[0] == 9);
    assert(camera_mosaic_pipeline.render_rgba8(camera_mosaic.failed(7), normalized[0..],
        output[0..], 4, 4, camera_mosaic_pipeline.fitted_mhc_v1, edit, scratch,
        no_cancel, 0
    ) == 7 and output[0] == 9);
    assert(camera_mosaic_pipeline.render_rgba8(image, normalized[0..],
        output[0..], 4, 4, camera_mosaic_pipeline.fitted_mhc_v1, edit, scratch,
        cancel, 7
    ) == 7 and output[0] == 9);
}

test "shared RGB16 route preserves fitted export bytes" {
    const image: camera_mosaic.CameraMosaic = {
        width: 4,
        height: 4,
        cfa: [0, 1, 1, 2],
        camera_to_xyz_d50: [0.96422, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.82521],
        neutral: [1.0, 1.0, 1.0],
        baseline_exposure_ev: 0.0,
        orientation: 1,
        status: 0
    };
    const normalized: [16]f32 = [0.5] ** 16;
    var output: [48]u16 = [0] ** 48;
    var reference: [48]u16 = [0] ** 48;
    const edit: camera_mosaic_pipeline.DevelopSettings = {
        exposure_ev: 0.5,
        contrast_percent: 0.0
    };
    assert(camera_mosaic_pipeline.render_rgb16(image, normalized[0..], output[0..],
        4, 4, camera_mosaic_pipeline.fitted_mhc_v1, edit,
        no_cancel, 0
    ) == 0);
    assert(mosaic_render.render_oriented_bayer_rgb16_v8(
        normalized[0..].ptr as! *const f32, 16, 4, 4,
        image.cfa[0..].ptr as! *const u32, 4,
        image.camera_to_xyz_d50[0..].ptr as! *const f64, 9,
        reference[0..].ptr as! *u16, 48, 4, 4,
        0.0, 0.5, 2, 1, no_cancel, 0
    ) == 0);
    var index: usize = 0;
    while index < 48 {
        assert(output[index] == reference[index]);
        index = index + 1;
    }
}

test "fitted working preview encodes to the existing neutral RGBA8 bytes" {
    const normalized: [16]f32 = [0.5] ** 16;
    const cfa: [4]u32 = [0, 1, 1, 2];
    const matrix: [9]f64 = [0.96422, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.82521];
    var working: [48]f64 = [0.0] ** 48;
    var actual: [64]u8 = [0] ** 64;
    var expected: [64]u8 = [0] ** 64;
    assert(mosaic_render.prepare_oriented_working_preview(normalized[0..], 4, 4, cfa, matrix, working[0..], 4, 4, 1, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_raw(working[0..].ptr as! *const f64, 48, actual[0..].ptr as! *u8, 64, 4, 4, 0.0, 0.0, 1.0, no_cancel, 0) == 0);
    assert(mosaic_render.render_oriented_rgba8(normalized[0..], 4, 4, cfa, matrix, expected[0..], 4, 4, 0.0, 0.0, 2, 1, no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 64 {
        assert(actual[index] == expected[index]);
        index = index + 1;
    }
}

test "oriented source region matches the same pixels in a full working frame" {
    const normalized: [16]f32 = [
        0.05, 0.12, 0.19, 0.26,
        0.33, 0.40, 0.47, 0.54,
        0.61, 0.68, 0.75, 0.82,
        0.89, 0.96, 1.03, 1.10
    ];
    const cfa: [4]u32 = [0, 1, 1, 2];
    const matrix: [9]f64 = [0.96422, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.82521];
    var full: [48]f64 = [0.0] ** 48;
    var region: [12]f64 = [0.0] ** 12;
    assert(mosaic_render.prepare_oriented_working_preview(normalized[0..],
        4, 4, cfa, matrix, full[0..], 4, 4, 6, no_cancel, 0
    ) == 0);
    assert(mosaic_render.prepare_oriented_working_region(normalized[0..],
        4, 4, cfa, matrix, 6, 1, 1, 2, 2, region[0..],
        2, 2, no_cancel, 0
    ) == 0);
    var row: usize = 0;
    while row < 2 {
        var column: usize = 0;
        while column < 2 {
            var channel: usize = 0;
            while channel < 3 {
                assert(region[(row * 2 + column) * 3 + channel] ==
                    full[((row + 1) * 4 + column + 1) * 3 + channel]
                );
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    assert(mosaic_render.prepare_oriented_working_region(normalized[0..],
        4, 4, cfa, matrix, 6, 3, 1, 2, 2, region[0..],
        2, 2, no_cancel, 0
    ) == 4);
    assert(mosaic_render.prepare_oriented_working_region(normalized[0..],
        4, 4, cfa, matrix, 6, 1, 1, 2, 2, region[0..],
        2, 2, cancel, 7
    ) == 7);
}
