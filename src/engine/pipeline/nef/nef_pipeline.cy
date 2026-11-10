import .engine.core.cancellation;
import { Highlight } from .engine.core.camera_contract;
import .engine.raw.nef.nef_source;
import .engine.raw.nef.nef_mosaic;
import .engine.render.mosaic_render;

pub struct PreviewSize {
    pub stored_pixels: usize;
    pub crop_pixels: usize;
    pub visual_width: usize;
    pub visual_height: usize;
    pub status: i32;
}

pub fn inspect_preview(source: []const u8): PreviewSize {
    const info = nef_source.inspect_source(source);
    var result: PreviewSize = {
        stored_pixels: 0,
        crop_pixels: 0,
        visual_width: 0,
        visual_height: 0,
        status: info.status
    };
    if info.status != 0 {
        return result;
    }
    result.stored_pixels = (info.storage.width as usize) * (info.storage.height as usize);
    result.crop_pixels = (info.maker.crop[2] as usize) * (info.maker.crop[3] as usize);
    result.visual_width = info.maker.crop[2] as usize;
    result.visual_height = info.maker.crop[3] as usize;
    if info.storage.orientation >= 5 {
        result.visual_width = info.maker.crop[3] as usize;
        result.visual_height = info.maker.crop[2] as usize;
    }
    return result;
}

// Decode a supported Nikon NEF source into an oriented, fitted MHC
// scene-linear working preview. The caller owns exact sensor, crop and RGB
// buffers; dimensions are bounded like the RGBA8 preview route.
pub fn prepare_working(source: []const u8, samples: []u16, normalized: []f32,
    working: []f64, width: usize, height: usize,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if width == 0 or height == 0 or width > 2048 or height > 2048 or
    width > 4194304 / height or working.len() != width * height * 3 {
        return 4;
    }
    return prepare_working_full(source, samples, normalized, working, width,
        height, cancelled, context
    );
}

// Full visual-size working RGB for a supported Nikon NEF route. This
// reuses the preview's decode, orientation and MHC characterization math;
// only the requested output geometry and resource ceiling differ.
pub fn prepare_working_full(source: []const u8, samples: []u16, normalized: []f32,
    working: []f64, width: usize, height: usize,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if width == 0 or height == 0 or width > 10000 or height > 10000 or
    width > 50000000 / height or working.len() != width * height * 3 {
        return 4;
    }
    const info = nef_source.inspect_source(source);
    if info.status != 0 {
        return info.status;
    }
    var visual_width = info.maker.crop[2] as usize;
    var visual_height = info.maker.crop[3] as usize;
    if info.storage.orientation >= 5 {
        visual_width = info.maker.crop[3] as usize;
        visual_height = info.maker.crop[2] as usize;
    }
    if width > visual_width or height > visual_height {
        return 4;
    }
    const mosaic = nef_mosaic.decode_normalized(source, samples, normalized,
        50000000, cancelled, context
    );
    if mosaic.status != 0 {
        return mosaic.status;
    }
    return mosaic_render.prepare_oriented_working_preview_highlight(normalized,
        mosaic.width, mosaic.height, mosaic.cfa, mosaic.camera_to_xyz_d50,
        mosaic.neutral, working, width, height, mosaic.orientation,
        Highlight.two_channel_neutral as u32, cancelled, context
    );
}

// Decode a bounded Nikon NEF once and reconstruct only a requested
// upright source-pixel rectangle. Coordinates are zero-based after orientation.
// Source and decoded sensor buffers stay caller-owned; no fitted preview is
// involved. Equal rectangle/output extents preserve original pixel geometry.
pub fn prepare_working_region(source: []const u8, samples: []u16,
    normalized: []f32, left: usize, top: usize,
    region_width: usize, region_height: usize, working: []f64,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if region_width == 0 or region_height == 0 or
    region_width > 4194304 / region_height or
    working.len() != region_width * region_height * 3 {
        return 4;
    }
    const info = nef_source.inspect_source(source);
    if info.status != 0 {
        return info.status;
    }
    var visual_width = info.maker.crop[2] as usize;
    var visual_height = info.maker.crop[3] as usize;
    if info.storage.orientation >= 5 {
        visual_width = info.maker.crop[3] as usize;
        visual_height = info.maker.crop[2] as usize;
    }
    if left >= visual_width or top >= visual_height or
    region_width > visual_width - left or
    region_height > visual_height - top {
        return 4;
    }
    const mosaic = nef_mosaic.decode_normalized(source, samples, normalized,
        50000000, cancelled, context
    );
    if mosaic.status != 0 {
        return mosaic.status;
    }
    return mosaic_render.prepare_oriented_working_region_highlight(normalized,
        mosaic.width, mosaic.height, mosaic.cfa, mosaic.camera_to_xyz_d50,
        mosaic.neutral, mosaic.orientation, left, top, region_width,
        region_height, working, region_width, region_height,
        Highlight.two_channel_neutral as u32, cancelled, context
    );
}

// Headless Nikon NEF fitted preview v1. Source bytes remain immutable.
// Caller owns exact stored u16, cropped camera-linear f32, and RGBA8 buffers.
// Output dimensions are oriented visual pixels, at most 2048 on each axis and
// 4,194,304 total. Zero user EV preserves the as-shot baseline. Nonzero status
// invalidates output; cancellation is polled during decode and rendering.
pub fn render(source: []const u8, samples: []u16, normalized: []f32,
    output: []u8, width: usize, height: usize, user_exposure_ev: f64,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if width == 0 or height == 0 or width > 2048 or height > 2048 or
    width > 4194304 / height or output.len() != width * height * 4 or
    not (user_exposure_ev >= -4.0 and user_exposure_ev <= 4.0) {
        return 4;
    }
    const source_info = nef_source.inspect_source(source);
    if source_info.status != 0 {
        return source_info.status;
    }
    var visual_width = source_info.maker.crop[2] as usize;
    var visual_height = source_info.maker.crop[3] as usize;
    if source_info.storage.orientation >= 5 {
        visual_width = source_info.maker.crop[3] as usize;
        visual_height = source_info.maker.crop[2] as usize;
    }
    if width > visual_width or height > visual_height {
        return 4;
    }
    const mosaic = nef_mosaic.decode_normalized(source, samples, normalized,
        50000000, cancelled, context
    );
    if mosaic.status != 0 {
        return mosaic.status;
    }
    return mosaic_render.render_oriented_rgba8_highlight(normalized,
        mosaic.width, mosaic.height, mosaic.cfa, mosaic.camera_to_xyz_d50,
        mosaic.neutral, output, width, height, mosaic.baseline_exposure_ev,
        user_exposure_ev, mosaic.orientation, cancelled, context
    );
}

// Full visual-resolution RGB16 encoded sRGB for a TIFF-capable headless
// caller. The caller supplies exactly three u16 samples per oriented pixel;
// the engine does not write a TIFF container or attach the output ICC here.
// Output is invalid on any nonzero status, including cancellation.
pub fn render_rgb16(source: []const u8, samples: []u16, normalized: []f32,
    output: []u16, user_exposure_ev: f64,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not (user_exposure_ev >= -4.0 and user_exposure_ev <= 4.0) {
        return 4;
    }
    const source_info = nef_source.inspect_source(source);
    if source_info.status != 0 {
        return source_info.status;
    }
    var width = source_info.maker.crop[2] as usize;
    var height = source_info.maker.crop[3] as usize;
    if source_info.storage.orientation >= 5 {
        width = source_info.maker.crop[3] as usize;
        height = source_info.maker.crop[2] as usize;
    }
    if width == 0 or height == 0 or width > 50000000 / height or output.len() != width * height * 3 {
        return 4;
    }
    const mosaic = nef_mosaic.decode_normalized(source, samples, normalized,
        50000000, cancelled, context
    );
    if mosaic.status != 0 {
        return mosaic.status;
    }
    return mosaic_render.render_oriented_rgb16_highlight(normalized,
        mosaic.width, mosaic.height, mosaic.cfa, mosaic.camera_to_xyz_d50,
        mosaic.neutral, output, width, height, mosaic.baseline_exposure_ev,
        user_exposure_ev, mosaic.orientation, cancelled, context
    );
}
