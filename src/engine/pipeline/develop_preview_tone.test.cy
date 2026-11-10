import .engine.pipeline.spatial_camera_pipeline;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    return context == 7;
}

test "preview tone controls retain neutral output and affect their own bands" {
    const working: [9]f64 = [0.1, 0.1, 0.1, 0.5, 0.5, 0.5, 1.2, 1.2, 1.2];
    var baseline: [12]u8 = [0] ** 12;
    var neutral: [12]u8 = [0] ** 12;
    var shadows: [12]u8 = [0] ** 12;
    var highlights: [12]u8 = [0] ** 12;
    assert(spatial_camera_pipeline.render_prepared_raw(working[0..].ptr, 9, baseline[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr, 9, neutral[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 0.0, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr, 9, shadows[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 1.0, 0.0, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr, 9, highlights[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 1.0, no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 12 {
        assert(baseline[index] == neutral[index]);
        index = index + 1;
    }
    assert(shadows[0] > baseline[0] and shadows[4] == baseline[4]);
    assert(highlights[0] == baseline[0] and highlights[4] > baseline[4]);
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr, 9, neutral[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 1.1, 0.0, no_cancel, 0) == 5);
}

test "endpoint tone v2 preserves neutral bytes and separates black and white regions" {
    const working: [9]f64 = [0.02, 0.02, 0.02, 0.35, 0.35, 0.35, 0.75, 0.75, 0.75];
    var baseline: [12]u8 = [0] ** 12;
    var neutral: [12]u8 = [0] ** 12;
    var blacks: [12]u8 = [0] ** 12;
    var whites: [12]u8 = [0] ** 12;
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr, 9, baseline[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 0.0, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_endpoints(working[0..].ptr, 9, neutral[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_endpoints(working[0..].ptr, 9, blacks[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.02, 0.0, 0.0, 0.0, no_cancel, 0) == 0);
    assert(spatial_camera_pipeline.render_prepared_endpoints(working[0..].ptr, 9, whites[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.5, no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 12 {
        assert(baseline[index] == neutral[index]);
        index = index + 1;
    }
    assert(blacks[0] < baseline[0] and blacks[4] < baseline[4]);
    assert(whites[0] == baseline[0] and whites[4] == baseline[4] and whites[8] > baseline[8]);
    neutral[0] = 17;
    assert(spatial_camera_pipeline.render_prepared_endpoints(working[0..].ptr, 9, neutral[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.126, 0.0, 0.0, 0.0, no_cancel, 0) == 5 and neutral[0] == 17);
    assert(spatial_camera_pipeline.render_prepared_endpoints(working[0..].ptr, 9, neutral[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.01, no_cancel, 0) == 5 and neutral[0] == 17);
    assert(spatial_camera_pipeline.render_prepared_endpoints(working[0..].ptr, 9, neutral[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.02, 0.0, 0.0, 0.0, cancel, 7) == 7 and neutral[0] == 17);
}
