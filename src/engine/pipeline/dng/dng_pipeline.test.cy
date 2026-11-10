import std.fs;
import .engine.pipeline.dng.dng_pipeline;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.develop.contrast;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    const ignored = context;
    return true;
}

test "Ricoh compressed DNG baseline composition renders a bounded frame" {
    const path = "target/native-source-corpus/Ricoh-GR-IIIx.DNG";
    const present = fs.exists(path) catch (error) {
        return;
    };
    if not present {
        return;
    }
    const bytes = fs.read_bytes(path) catch (error) {
        assert(false);
        return;
    };
    const source = bytes[0..bytes.len()];
    const size = dng_pipeline.inspect(source, 64 * 1024 * 1024);
    assert(size.status == 0);
    var samples: [:]u16 = [];
    samples.reserve(size.stored_pixels);
    var i: usize = 0;
    while i < size.stored_pixels {
        samples.push(0);
        i = i + 1;
    }
    var normalized: [:]f32 = [];
    normalized.reserve(size.crop_pixels);
    i = 0;
    while i < size.crop_pixels {
        normalized.push(0.0);
        i = i + 1;
    }
    var output: [640]u8 = [0] ** 640;
    const status = dng_pipeline.render_baseline(source, samples[0..samples.len()], normalized[0..normalized.len()], output[0..], 16, 10, 64 * 1024 * 1024, no_cancel, 0);
    assert(status == 0);
    assert(output[3] == 255 and output[639] == 255);
    var total: usize = 0;
    var weighted: usize = 0;
    i = 0;
    while i < 640 {
        total = total + output[i] as usize;
        weighted = weighted + (i + 1) * output[i] as usize;
        i = i + 1;
    }
    // These pins match the Rust baseline route on this exact source and size.
    assert(total == 78287);
    assert(weighted == 26099498);
    output[0] = 91;
    assert(dng_pipeline.render_baseline(source, samples[0..samples.len()], normalized[0..normalized.len()], output[0..], 16, 10, 64 * 1024 * 1024, cancel, 0) == 7);
    assert(output[0] == 91);
    const need = spatial_camera_pipeline.spatial_requirements(size.crop_width, size.crop_height);
    assert(need.status == 0);
    var camera: [:]f32 = [];
    camera.reserve(need.camera_channels);
    i = 0;
    while i < need.camera_channels {
        camera.push(0.0);
        i = i + 1;
    }
    var band: [:]f64 = [];
    band.reserve(need.band_channels);
    i = 0;
    while i < need.band_channels {
        band.push(0.0);
        i = i + 1;
    }
    var source_pyramid: [:]f32 = [];
    source_pyramid.reserve(need.source_channels);
    i = 0;
    while i < need.source_channels {
        source_pyramid.push(0.0);
        i = i + 1;
    }
    var rim: [:]f32 = [];
    rim.reserve(need.rim_channels);
    i = 0;
    while i < need.rim_channels {
        rim.push(0.0);
        i = i + 1;
    }
    var lum: [:]f32 = [];
    lum.reserve(need.coarse_pixels);
    i = 0;
    while i < need.coarse_pixels {
        lum.push(0.0);
        i = i + 1;
    }
    var touched: [:]u8 = [];
    touched.reserve(need.coarse_pixels);
    var near: [:]u8 = [];
    near.reserve(need.coarse_pixels);
    i = 0;
    while i < need.coarse_pixels {
        touched.push(0);
        near.push(0);
        i = i + 1;
    }
    const spatial_status = dng_pipeline.render_spatial_headroom(source, samples[0..samples.len()], normalized[0..normalized.len()], camera[0..camera.len()], band[0..band.len()], source_pyramid[0..source_pyramid.len()], rim[0..rim.len()], lum[0..lum.len()], touched[0..touched.len()], near[0..near.len()], output[0..], 16, 10, 64 * 1024 * 1024, no_cancel, 0);
    assert(spatial_status == 0);
    total = 0;
    weighted = 0;
    i = 0;
    while i < 640 {
        total = total + output[i] as usize;
        weighted = weighted + (i + 1) * output[i] as usize;
        i = i + 1;
    }
    // Same source, route, and dimensions as the Rust product preview pin.
    assert(total == 78298);
    assert(weighted == 26102800);
    const expected = fs.read_bytes("src/engine/tests/fixtures/ricoh-spatial-headroom-v5-16x10.rgba8") catch (error) {
        assert(false);
        return;
    };
    assert(expected.len() == 640);
    i = 0;
    while i < 640 {
        assert(output[i] == expected[i]);
        i = i + 1;
    }
    const neutral_total = total;
    const brighter = dng_pipeline.render_spatial_headroom_with_exposure(source, samples[0..samples.len()], normalized[0..normalized.len()], camera[0..camera.len()], band[0..band.len()], source_pyramid[0..source_pyramid.len()], rim[0..rim.len()], lum[0..lum.len()], touched[0..touched.len()], near[0..near.len()], output[0..], 16, 10, 1.0, 64 * 1024 * 1024, no_cancel, 0);
    assert(brighter == 0);
    var brighter_total: usize = 0;
    i = 0;
    while i < 640 {
        brighter_total = brighter_total + output[i] as usize;
        i = i + 1;
    }
    assert(brighter_total > neutral_total);
    var expected_exposed: [640]u8 = [0] ** 640;
    i = 0;
    while i < 640 {
        expected_exposed[i] = output[i];
        i = i + 1;
    }
    output[0] = 91;
    assert(dng_pipeline.render_spatial_headroom_with_exposure(source, samples[0..samples.len()], normalized[0..normalized.len()], camera[0..camera.len()], band[0..band.len()], source_pyramid[0..source_pyramid.len()], rim[0..rim.len()], lum[0..lum.len()], touched[0..touched.len()], near[0..near.len()], output[0..], 16, 10, 17.0, 64 * 1024 * 1024, no_cancel, 0) == 4);
    assert(output[0] == 91);
    const contrasted = dng_pipeline.render_spatial_headroom_with_develop(source, samples[0..samples.len()], normalized[0..normalized.len()], camera[0..camera.len()], band[0..band.len()], source_pyramid[0..source_pyramid.len()], rim[0..rim.len()], lum[0..lum.len()], touched[0..touched.len()], near[0..near.len()], output[0..], 16, 10, 0.0, 40.0, 64 * 1024 * 1024, no_cancel, 0);
    assert(contrasted == 0);
    var changed: usize = 0;
    i = 0;
    while i < 640 {
        if output[i] != expected[i] {
            changed = changed + 1;
        }
        i = i + 1;
    }
    assert(changed > 0);
    const prepared = dng_pipeline.prepare_spatial_camera(source, samples[0..samples.len()], normalized[0..normalized.len()], camera[0..camera.len()], band[0..band.len()], source_pyramid[0..source_pyramid.len()], rim[0..rim.len()], lum[0..lum.len()], touched[0..touched.len()], near[0..near.len()], 64 * 1024 * 1024, no_cancel, 0);
    assert(prepared.status == 0);
    var cached: [640]u8 = [0] ** 640;
    assert(dng_pipeline.render_prepared_spatial_camera(prepared, camera[0..camera.len()], cached[0..], 16, 10, 0.0, 40.0, no_cancel, 0) == 0);
    i = 0;
    while i < 640 {
        assert(cached[i] == output[i]);
        i = i + 1;
    }
    assert(dng_pipeline.render_prepared_spatial_camera(prepared, camera[0..camera.len()], cached[0..], 16, 10, 17.0, 40.0, no_cancel, 0) == 4);
    var working: [480]f64 = [0.0] ** 480;
    assert(spatial_camera_pipeline.prepare_working_preview(camera[0..camera.len()], prepared.width, prepared.height, prepared.camera_to_xyz_d50, prepared.orientation, working[0..], 16, 10, no_cancel, 0) == 0);
    var fast: [640]u8 = [0] ** 640;
    assert(spatial_camera_pipeline.render_prepared_raw(working[0..].ptr as! *const f64, 480, fast[0..].ptr as! *u8, 640, 16, 10, prepared.baseline_exposure_ev, 0.0, 1.0, no_cancel, 0) == 0);
    const expected_neutral = fs.read_bytes("src/engine/tests/fixtures/ricoh-spatial-headroom-v5-16x10.rgba8") catch (error) {
        assert(false);
        return;
    };
    i = 0;
    while i < 640 {
        assert(fast[i] == expected_neutral[i]);
        i = i + 1;
    }
    assert(spatial_camera_pipeline.render_prepared_raw(working[0..].ptr as! *const f64, 480, fast[0..].ptr as! *u8, 640, 16, 10, prepared.baseline_exposure_ev, 0.0, 1.5, cancel, 0) == 7);
    assert(spatial_camera_pipeline.render_prepared_raw(working[0..].ptr as! *const f64, 480, fast[0..].ptr as! *u8, 640, 16, 10, prepared.baseline_exposure_ev, 1.0, 1.0, no_cancel, 0) == 0);
    i = 0;
    while i < 640 {
        assert(fast[i] == expected_exposed[i]);
        i = i + 1;
    }
    assert(spatial_camera_pipeline.render_prepared_raw(working[0..].ptr as! *const f64, 480, fast[0..].ptr as! *u8, 640, 16, 10, prepared.baseline_exposure_ev, 0.0, contrast.slope_from_percent_native(40.0), no_cancel, 0) == 0);
    i = 0;
    while i < 640 {
        assert(fast[i] == output[i]);
        i = i + 1;
    }
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr as! *const f64, 480, fast[0..].ptr as! *u8, 640, 16, 10, prepared.baseline_exposure_ev, 0.0, 1.0, 0.6, -0.6, no_cancel, 0) == 0);
    var tone_changed: usize = 0;
    i = 0;
    while i < 640 {
        if fast[i] != expected_neutral[i] {
            tone_changed = tone_changed + 1;
        }
        i = i + 1;
    }
    assert(tone_changed > 0);

}
