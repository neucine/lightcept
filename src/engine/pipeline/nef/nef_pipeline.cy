import .engine.core.cancellation;
import .engine.raw.nef.nef_source;
import .engine.raw.nef.nef_mosaic;
import .engine.pipeline.camera_mosaic_pipeline;

// Headless Z8 lossless NEF fitted preview v1. Source bytes remain immutable.
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
    var empty_band: [0]f64 = [];
    const scratch: camera_mosaic_pipeline.SpatialScratch = {
        camera: normalized[0..0],
        band: empty_band[0..],
        source_pyramid: normalized[0..0],
        rim: normalized[0..0],
        lum: normalized[0..0],
        touched: output[0..0],
        near: output[0..0]
    };
    const edit: camera_mosaic_pipeline.DevelopSettings = {
        exposure_ev: user_exposure_ev,
        contrast_percent: 0.0
    };
    return camera_mosaic_pipeline.render_rgba8(mosaic, normalized, output,
        width, height, camera_mosaic_pipeline.fitted_mhc_v1,
        edit, scratch, cancelled, context
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
    const edit: camera_mosaic_pipeline.DevelopSettings = {
        exposure_ev: user_exposure_ev,
        contrast_percent: 0.0
    };
    return camera_mosaic_pipeline.render_rgb16(mosaic, normalized, output,
        width, height, camera_mosaic_pipeline.fitted_mhc_v1,
        edit, cancelled, context
    );
}
