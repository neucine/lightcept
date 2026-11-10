import lightcept_core.engine.pipeline.dng.dng_pipeline;
import lightcept_core.engine.pipeline.spatial_camera_pipeline;
import lightcept_core.engine.pipeline.preview_develop_plan;
import { file_size, read_file, publish_frame, publish_prepared, should_cancel } from .native_preview;

fn cancel_if_stale(context: usize): bool {
    const ignored = context;
    return should_cancel();
}

// Source bytes, sensor samples and all processing scratch are owned for this
// invocation. Publication copies only a fully rendered RGBA8 frame.
pub fn open(path: *const u8, generation: u32, exposure_tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32): i32 {
    if (path as! usize) == 0 {
        return 4;
    }
    if exposure_tenths < -160 or exposure_tenths > 160 or contrast_percent < -100 or contrast_percent > 100 or shadows_percent < -100 or shadows_percent > 100 or highlights_percent < -100 or highlights_percent > 100 or blacks_percent < -100 or blacks_percent > 100 or whites_percent < -100 or whites_percent > 100 {
        return 4;
    }
    if should_cancel() {
        return 7;
    }
    const source_length = file_size(path);
    if source_length < 8 or source_length > 512 * 1024 * 1024 {
        return 1;
    }
    var source: [:]u8 = [: source_length as usize]u8;
    while source.len() < source_length as usize {
        source.push(0);
    }
    if read_file(path, source[..].ptr, source_length) != 0 {
        return 1;
    }
    if should_cancel() {
        return 7;
    }
    const size = dng_pipeline.inspect(source[..], 33554432);
    if size.status != 0 {
        return size.status;
    }
    const need = spatial_camera_pipeline.spatial_requirements(size.crop_width, size.crop_height);
    if need.status != 0 {
        return need.status;
    }
    var width = size.crop_width;
    var height = size.crop_height;
    if width > 2048 or height > 2048 {
        if width >= height {
            height = height * 2048 / width;
            width = 2048;
        } else {
            width = width * 2048 / height;
            height = 2048;
        }
    }
    if width == 0 {
        width = 1;
    }
    if height == 0 {
        height = 1;
    }
    if height > 4194304 / width {
        return 4;
    }
    var samples: [:]u16 = [: size.stored_pixels]u16;
    while samples.len() < size.stored_pixels {
        samples.push(0);
    }
    var normalized: [:]f32 = [: size.crop_pixels]f32;
    while normalized.len() < size.crop_pixels {
        normalized.push(0.0);
    }
    var camera: [:]f32 = [: need.camera_channels]f32;
    while camera.len() < need.camera_channels {
        camera.push(0.0);
    }
    var band: [:]f64 = [: need.band_channels]f64;
    while band.len() < need.band_channels {
        band.push(0.0);
    }
    var pyramid: [:]f32 = [: need.source_channels]f32;
    while pyramid.len() < need.source_channels {
        pyramid.push(0.0);
    }
    var rim: [:]f32 = [: need.rim_channels]f32;
    while rim.len() < need.rim_channels {
        rim.push(0.0);
    }
    var lum: [:]f32 = [: need.coarse_pixels]f32;
    while lum.len() < need.coarse_pixels {
        lum.push(0.0);
    }
    var touched: [:]u8 = [: need.coarse_pixels]u8;
    while touched.len() < need.coarse_pixels {
        touched.push(0);
    }
    var near: [:]u8 = [: need.coarse_pixels]u8;
    while near.len() < need.coarse_pixels {
        near.push(0);
    }
    var output: [:]u8 = [: width * height * 4]u8;
    while output.len() < width * height * 4 {
        output.push(0);
    }
    const prepared = dng_pipeline.prepare_spatial_camera(source[..], samples[..], normalized[..], camera[..], band[..], pyramid[..], rim[..], lum[..], touched[..], near[..], 33554432, cancel_if_stale, 0);
    if prepared.status != 0 {
        return prepared.status;
    }
    var working: [:]f64 = [: width * height * 3]f64;
    while working.len() < width * height * 3 {
        working.push(0.0);
    }
    const working_status = spatial_camera_pipeline.prepare_working_preview(camera[..], prepared.width, prepared.height, prepared.camera_to_xyz_d50, prepared.orientation, working[..], width, height, cancel_if_stale, 0);
    if working_status != 0 {
        return working_status;
    }
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: exposure_tenths,
        contrast_percent: contrast_percent,
        shadows_percent: shadows_percent,
        highlights_percent: highlights_percent,
        blacks_percent: blacks_percent,
        whites_percent: whites_percent,
        warmth_percent: warmth_percent,
        tint_percent: tint_percent,
        vibrance_percent: vibrance_percent,
        saturation_percent: saturation_percent,
        clarity_percent: clarity_percent,
        texture_percent: texture_percent
    };
    const status = preview_develop_plan.render(working[..].ptr as! *const f64, working.len(), output[..].ptr as! *u8, output.len(), width, height, prepared.baseline_exposure_ev, controls, cancel_if_stale, 0);
    if status != 0 {
        return status;
    }
    const published = publish_frame(output[..].ptr as! *const u8, output.len(), width, height, generation);
    if published != 0 {
        return published;
    }
    const baseline: [1]f64 = [prepared.baseline_exposure_ev];
    var source_width = prepared.width;
    var source_height = prepared.height;
    if prepared.orientation >= 5 {
        source_width = prepared.height;
        source_height = prepared.width;
    }
    return publish_prepared(working[..].ptr as! *const f64, working.len(), baseline[0..].ptr as! *const f64, width, height, source_width, source_height, generation);
}

// Native borrowed buffers remain valid only for this synchronous render.
pub fn render_cached(working: *const u8, working_bytes: usize, baseline: *const u8, output: *u8, output_bytes: usize, width: usize, height: usize, exposure_tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32): i32 {
    var default_exposure: f64 = 0.0;
    unchecked {
        default_exposure = *(baseline as! *const f64);
    }
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: exposure_tenths,
        contrast_percent: contrast_percent,
        shadows_percent: shadows_percent,
        highlights_percent: highlights_percent,
        blacks_percent: blacks_percent,
        whites_percent: whites_percent,
        warmth_percent: warmth_percent,
        tint_percent: tint_percent,
        vibrance_percent: vibrance_percent,
        saturation_percent: saturation_percent,
        clarity_percent: clarity_percent,
        texture_percent: texture_percent
    };
    return preview_develop_plan.render(working as! *const f64, working_bytes / 8, output, output_bytes, width, height, default_exposure, controls, cancel_if_stale, 0);
}
