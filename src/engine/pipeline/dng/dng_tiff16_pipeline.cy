import .engine.pipeline.dng.dng_pipeline;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.pipeline.preview_develop_plan;
import .engine.tiff.rgb16_writer;

// Headless developed RGB16 TIFF for a bounded compressed DNG. Source bytes
// are immutable. Every scratch and output buffer has exact caller-owned shape;
// a nonzero result invalidates the TIFF buffer. The route uses the same
// spatial camera preparation and twelve-control plan as Neiv's fitted preview,
// at the source's visual dimensions. The TIFF is encoded sRGB with caller ICC.
pub fn render_developed(source: []const u8, samples: []u16,
    normalized: []f32, camera: []f32, band: []f64,
    source_pyramid: []f32, rim: []f32, lum: []f32,
    touched: []u8, near: []u8, working: []f64,
    rgb16: []u16, icc: []const u8, tiff: []u8,
    controls: preview_develop_plan.Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    const size = dng_pipeline.inspect(source, 33554432);
    if size.status != 0 {
        return size.status;
    }
    const need = spatial_camera_pipeline.spatial_requirements(
        size.crop_width, size.crop_height
    );
    if need.status != 0 {
        return need.status;
    }
    var width = size.crop_width;
    var height = size.crop_height;
    // DNG orientation is determined by the source adapter after preparation;
    // both possible visual orientations have the same pixel count.
    const plan = rgb16_writer.layout(width, height, icc.len());
    if plan.status != 0 {
        return plan.status;
    }
    if samples.len() != size.stored_pixels or normalized.len() != size.crop_pixels or
    camera.len() != need.camera_channels or band.len() != need.band_channels or
    source_pyramid.len() != need.source_channels or rim.len() != need.rim_channels or
    lum.len() != need.coarse_pixels or touched.len() != need.coarse_pixels or
    near.len() != need.coarse_pixels or working.len() != width * height * 3 or
    rgb16.len() != working.len() or tiff.len() != plan.total_bytes {
        return 4;
    }
    if not preview_develop_plan.valid(controls) {
        return 5;
    }
    const prepared = dng_pipeline.prepare_spatial_camera(source, samples,
        normalized, camera, band, source_pyramid, rim, lum, touched, near,
        33554432, cancelled, context
    );
    if prepared.status != 0 {
        return prepared.status;
    }
    if prepared.orientation >= 5 {
        width = size.crop_height;
        height = size.crop_width;
    }
    const oriented_plan = rgb16_writer.layout(width, height, icc.len());
    if oriented_plan.status != 0 or tiff.len() != oriented_plan.total_bytes {
        return 4;
    }
    const working_status = spatial_camera_pipeline.prepare_working_preview(
        camera, prepared.width, prepared.height, prepared.camera_to_xyz_d50,
        prepared.orientation, working, width, height, cancelled, context
    );
    if working_status != 0 {
        return working_status;
    }
    const rendered = preview_develop_plan.render_rgb16(working.ptr,
        working.len(), rgb16.ptr, rgb16.len(), width, height,
        prepared.baseline_exposure_ev, controls, cancelled, context
    );
    if rendered != 0 {
        return rendered;
    }
    return rgb16_writer.encode(rgb16, width, height, icc, tiff,
        cancelled, context
    );
}
