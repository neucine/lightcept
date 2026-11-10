import .engine.develop.contrast;
import .engine.develop.hsl_grading;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.render.working_rgb_render;

// Source-neutral preview develop controls. Exposure is tenths of an EV;
// every other value is a signed percentage. The source adapter supplies only
// prepared scene-linear Rec.2020/D65 RGB and its baseline exposure. Warmth
// and tint are relative to the camera's as shot working frame.
pub struct Controls {
    pub exposure_tenths: i32;
    pub contrast_percent: i32;
    pub shadows_percent: i32;
    pub highlights_percent: i32;
    pub blacks_percent: i32;
    pub whites_percent: i32;
    pub warmth_percent: i32;
    pub tint_percent: i32;
    pub vibrance_percent: i32;
    pub saturation_percent: i32;
    pub clarity_percent: i32;
    pub texture_percent: i32;
}

pub fn valid(controls: Controls): bool {
    return controls.exposure_tenths >= -160 and controls.exposure_tenths <= 160
    and controls.contrast_percent >= -100 and controls.contrast_percent <= 100
    and controls.shadows_percent >= -100 and controls.shadows_percent <= 100
    and controls.highlights_percent >= -100 and controls.highlights_percent <= 100
    and controls.blacks_percent >= -100 and controls.blacks_percent <= 100
    and controls.whites_percent >= -100 and controls.whites_percent <= 100
    and controls.warmth_percent >= -100 and controls.warmth_percent <= 100
    and controls.tint_percent >= -100 and controls.tint_percent <= 100
    and controls.vibrance_percent >= -100 and controls.vibrance_percent <= 100
    and controls.saturation_percent >= -100 and controls.saturation_percent <= 100
    and controls.clarity_percent >= -100 and controls.clarity_percent <= 100
    and controls.texture_percent >= -100 and controls.texture_percent <= 100;
}

pub fn white_strength(percent: i32): f64 {
    if percent < 0 {
        return (percent as f64) / 200.0;
    }
    return (percent as f64) / 100.0;
}

// Exact output is width * height * 4 opaque sRGB bytes. Status 5 rejects
// controls before touching output; shape and cancellation statuses are owned
// by the renderer. Input stays immutable and output is invalid on failure.
pub fn render(working: *const f64, working_length: usize, output: *u8, output_length: usize,
    width: usize, height: usize, baseline_exposure_ev: f64, controls: Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not valid(controls) {
        return 5;
    }
    return spatial_camera_pipeline.render_prepared_texture(working, working_length,
        output, output_length, width, height, baseline_exposure_ev,
        (controls.exposure_tenths as f64) / 10.0,
        contrast.slope_from_percent_native(controls.contrast_percent as f64),
        (controls.blacks_percent as f64) / 800.0,
        (controls.shadows_percent as f64) / 100.0,
        (controls.highlights_percent as f64) / 100.0,
        white_strength(controls.whites_percent), controls.warmth_percent,
        controls.tint_percent, controls.vibrance_percent, controls.saturation_percent,
        controls.clarity_percent, controls.texture_percent, cancelled, context
    );
}

// Headless full-size encoded sRGB RGB16 from an oriented scene-linear
// Rec.2020/D65 working frame. This keeps the preview control mapping and
// stage order; only output quantization differs. Caller owns all buffers.
pub fn render_rgb16(working: *const f64, working_length: usize,
    output: *u16, output_length: usize, width: usize, height: usize,
    baseline_exposure_ev: f64, controls: Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not valid(controls) {
        return 5;
    }
    return working_rgb_render.render_working_rgb16_with_detail(
        working, working_length, output, output_length, width, height,
        baseline_exposure_ev, (controls.exposure_tenths as f64) / 10.0,
        contrast.slope_from_percent_native(controls.contrast_percent as f64),
        (controls.blacks_percent as f64) / 800.0,
        (controls.shadows_percent as f64) / 100.0,
        (controls.highlights_percent as f64) / 100.0,
        white_strength(controls.whites_percent), controls.warmth_percent,
        controls.tint_percent, controls.vibrance_percent,
        controls.saturation_percent, controls.clarity_percent,
        controls.texture_percent, cancelled, context
    );
}

// HSL is applied to scene-linear working RGB before the existing scalar
// develop controls. The caller owns disjoint scratch of width * height * 3
// f64 values. Both output encodings use this identical stage order.
pub fn render_with_hsl(working: []const f64, scratch: []f64,
    output: []u8, width: usize, height: usize, baseline_exposure_ev: f64,
    controls: Controls, asset: &const hsl_grading.GradeAsset,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not valid(controls) {
        return 5;
    }
    const status = hsl_grading.apply_f64(working, width, height, asset,
        scratch, cancelled, context
    );
    if status != 0 {
        return status as i32;
    }
    return render(scratch.ptr as! *const f64, scratch.len(), output.ptr,
        output.len(), width, height, baseline_exposure_ev, controls,
        cancelled, context
    );
}

pub fn render_rgb16_with_hsl(working: []const f64, scratch: []f64,
    output: []u16, width: usize, height: usize, baseline_exposure_ev: f64,
    controls: Controls, asset: &const hsl_grading.GradeAsset,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not valid(controls) {
        return 5;
    }
    const status = hsl_grading.apply_f64(working, width, height, asset,
        scratch, cancelled, context
    );
    if status != 0 {
        return status as i32;
    }
    return render_rgb16(scratch.ptr as! *const f64, scratch.len(), output.ptr,
        output.len(), width, height, baseline_exposure_ev, controls,
        cancelled, context
    );
}
