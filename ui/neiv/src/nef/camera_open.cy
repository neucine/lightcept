import lightcept_core.engine.pipeline.nef.nef_pipeline;
import lightcept_core.engine.pipeline.preview_develop_plan;
import { file_size, read_file, publish_frame, publish_prepared, should_cancel } from .native_preview;

fn cancel_if_stale(context: usize): bool {
    const ignored = context;
    return should_cancel();
}

// The source and all decode buffers are private to this invocation. Only a
// completed frame and its fitted working RGB are published to the document.
pub fn open(path: *const u8, generation: u32, exposure_tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32): i32 {
    if (path as! usize) == 0 or exposure_tenths < -40 or exposure_tenths > 40 or contrast_percent < -100 or contrast_percent > 100 or shadows_percent < -100 or shadows_percent > 100 or highlights_percent < -100 or highlights_percent > 100 or blacks_percent < -100 or blacks_percent > 100 or whites_percent < -100 or whites_percent > 100 {
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
    const info = nef_pipeline.inspect_preview(source[..]);
    if info.status != 0 {
        return info.status;
    }
    const stored_pixels = info.stored_pixels;
    const crop_pixels = info.crop_pixels;
    const visual_width = info.visual_width;
    const visual_height = info.visual_height;
    if stored_pixels == 0 or stored_pixels > 50000000 or crop_pixels == 0 or crop_pixels > stored_pixels or visual_width == 0 or visual_height == 0 {
        return 3;
    }
    var width = visual_width;
    var height = visual_height;
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
    var samples: [:]u16 = [: stored_pixels]u16;
    while samples.len() < stored_pixels {
        samples.push(0);
    }
    var normalized: [:]f32 = [: crop_pixels]f32;
    while normalized.len() < crop_pixels {
        normalized.push(0.0);
    }
    var working: [:]f64 = [: width * height * 3]f64;
    while working.len() < width * height * 3 {
        working.push(0.0);
    }
    var output: [:]u8 = [: width * height * 4]u8;
    while output.len() < width * height * 4 {
        output.push(0);
    }
    const prepared = nef_pipeline.prepare_working(source[..], samples[..], normalized[..], working[..], width, height, cancel_if_stale, 0);
    if prepared != 0 {
        return prepared;
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
    const status = preview_develop_plan.render(working[..].ptr as! *const f64, working.len(), output[..].ptr as! *u8, output.len(), width, height, 0.0, controls, cancel_if_stale, 0);
    if status != 0 {
        return status;
    }
    const published = publish_frame(output[..].ptr as! *const u8, output.len(), width, height, generation);
    if published != 0 {
        return published;
    }
    const baseline: [1]f64 = [0.0];
    return publish_prepared(working[..].ptr as! *const f64, working.len(), baseline[0..].ptr as! *const f64, width, height, visual_width, visual_height, generation);
}
