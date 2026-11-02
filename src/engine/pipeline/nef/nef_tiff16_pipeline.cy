import .engine.raw.nef.nef_source;
import .engine.pipeline.nef.nef_pipeline;
import .engine.tiff.rgb16_writer;

// Headless Z8 lossless NEF to Classic TIFF RGB16 v1. The caller owns the
// immutable source and output ICC bytes, exact stored/cropped scratch, encoded
// RGB16 samples, and TIFF output bytes. No filesystem or product types enter
// this route. The output is valid only after status 0; a caller should publish
// it atomically after success. Cancellation is checked across all stages.
pub fn render(source: []const u8, samples: []u16, normalized: []f32,
    rgb16: []u16, icc: []const u8, tiff: []u8, user_exposure_ev: f64,
    cancelled: fn (usize): bool, context: usize
): i32 {
    const info = nef_source.inspect_source(source);
    if info.status != 0 {
        return info.status;
    }
    var width = info.maker.crop[2] as usize;
    var height = info.maker.crop[3] as usize;
    if info.storage.orientation >= 5 {
        width = info.maker.crop[3] as usize;
        height = info.maker.crop[2] as usize;
    }
    const plan = rgb16_writer.layout(width, height, icc.len());
    if plan.status != 0 {
        return plan.status;
    }
    if rgb16.len() != width * height * 3 or tiff.len() != plan.total_bytes {
        return 4;
    }
    const rendered = nef_pipeline.render_rgb16(source, samples, normalized, rgb16,
        user_exposure_ev, cancelled, context
    );
    if rendered != 0 {
        return rendered;
    }
    return rgb16_writer.encode(rgb16, width, height, icc, tiff, cancelled, context);
}
