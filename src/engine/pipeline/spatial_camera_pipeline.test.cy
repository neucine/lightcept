import .engine.pipeline.spatial_camera_pipeline;

fn no_cancel(context: *const c_uchar): c_int {
    const ignored = context;
    return 0;
}

test "spatial camera stage sizes its pyramids and renders a neutral mosaic" {
    const need = spatial_camera_pipeline.spatial_requirements(4, 4);
    assert(need.status == 0 and need.camera_channels == 48 and need.band_channels == 384);
    assert(need.source_channels == 15 and need.rim_channels == 4 and need.coarse_pixels == 4);
    assert(spatial_camera_pipeline.spatial_requirements(16777216, 2).status == 3);
    var normalized: [16]f32 = [0.5] ** 16;
    const cfa: [4]u32 = [0, 1, 1, 2];
    const matrix: [9]f64 = [0.96422, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.82521];
    const neutral: [3]f64 = [1.0, 1.0, 1.0];
    var camera: [48]f32 = [0.0] ** 48;
    var band: [384]f64 = [0.0] ** 384;
    var source: [15]f32 = [0.0] ** 15;
    var rim: [4]f32 = [0.0] ** 4;
    var lum: [4]f32 = [0.0] ** 4;
    var touched: [4]u8 = [0] ** 4;
    var near: [4]u8 = [0] ** 4;
    var output: [64]u8 = [0] ** 64;
    const status = spatial_camera_pipeline.render(normalized[0..], 4, 4, cfa, matrix[0..], neutral, 0.0, 1,
        camera[0..], band[0..], source[0..], rim[0..], lum[0..], touched[0..], near[0..], output[0..], 4, 4, no_cancel, 0 as! *const c_uchar
    );
    assert(status == 0 and output[3] == 255 and output[63] == 255);
    assert(output[0] > 0 and output[0] < 255);
    assert(spatial_camera_pipeline.render(normalized[0..], 4, 4, cfa, matrix[0..], neutral, 0.0, 1,
        camera[0..47], band[0..], source[0..], rim[0..], lum[0..], touched[0..], near[0..], output[0..], 4, 4, no_cancel, 0 as! *const c_uchar
    ) == 4);
}
