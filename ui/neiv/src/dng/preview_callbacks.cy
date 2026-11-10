import lightcept_core.engine.pipeline.dng.dng_legacy_preview_pipeline;
import lightcept_core.engine.render.dng.dng_preview_buffer;
import neiv.native_buffer;
import .dng.camera_open;
import { open_generation, open_exposure_tenths, open_contrast_percent, open_shadows_percent, open_highlights_percent, open_blacks_percent, open_whites_percent, open_warmth_percent, open_tint_percent, open_vibrance_percent, open_saturation_percent, open_clarity_percent, open_texture_percent } from .native_preview;

fn never_poll(context: usize): bool {
    const ignored = context;
    return false;
}

// @neiv-callback
pub fn open_camera_dng(path: *const u8): i32 {
    return camera_open.open(path, open_generation(), open_exposure_tenths(), open_contrast_percent(), open_shadows_percent(), open_highlights_percent(), open_blacks_percent(), open_whites_percent(), open_warmth_percent(), open_tint_percent(), open_vibrance_percent(), open_saturation_percent(), open_clarity_percent(), open_texture_percent());
}

// @neiv-callback
pub fn dng_info(input: native_buffer.ReadBuffer, width: *u32, height: *u32): i32 {
    if (width as! usize) == 0 or (height as! usize) == 0 or input.length < 8 or input.length > dng_preview_buffer.source_byte_limit() {
        return 1;
    }
    const info = dng_preview_buffer.probe_raw(input.pointer, input.length);
    if info.status != 0 {
        return info.status as i32;
    }
    if info.width == 0 or info.height == 0 or (info.width as usize) > dng_preview_buffer.source_pixel_limit() or (info.height as usize) > dng_preview_buffer.source_pixel_limit() {
        return 4;
    }
    unchecked {
        *width = info.width as u32;
        *height = info.height as u32;
    }
    return 0;
}

// @neiv-callback
pub fn render_dng(input: native_buffer.ReadBuffer, output: native_buffer.WriteBuffer, width: usize, height: usize): i32 {
    return dng_legacy_preview_pipeline.render_fitted_raw(input.pointer, input.length, output.pointer,
        output.length, width, height,
        never_poll, 0
    );
}

// @neiv-callback
pub fn render_prepared_dng(working: native_buffer.ReadBuffer, baseline: native_buffer.ReadBuffer, output: native_buffer.WriteBuffer, width: usize, height: usize, exposure_tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32): i32 {
    if width == 0 or height == 0 or height > 4194304 / width or working.length != width * height * 3 * 8 or baseline.length != 8 or output.length != width * height * 4 or exposure_tenths < -160 or exposure_tenths > 160 or contrast_percent < -100 or contrast_percent > 100 or shadows_percent < -100 or shadows_percent > 100 or highlights_percent < -100 or highlights_percent > 100 or blacks_percent < -100 or blacks_percent > 100 or whites_percent < -100 or whites_percent > 100 {
        return 4;
    }
    return camera_open.render_cached(working.pointer, working.length, baseline.pointer, output.pointer, output.length, width, height, exposure_tenths, contrast_percent, shadows_percent, highlights_percent, blacks_percent, whites_percent, warmth_percent, tint_percent, vibrance_percent, saturation_percent, clarity_percent, texture_percent);
}
