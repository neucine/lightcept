import .engine.develop.crop;
import .engine.develop.straighten;
import .engine.develop.photo_geometry;
import .engine.develop.orthogonal_transform;
import .engine.pipeline.preview_develop_plan;
import .engine.tiff.rgb16_writer;
import .engine.render.working_rgb_resample;

// Scene-linear Rec.2020/D65 f64 geometry in upright source coordinates.
// Straighten retains the source extent; crop selects the output extent.
// The caller owns immutable input, disjoint full-size rotated scratch when
// angle is nonzero, and exact cropped output. A nonzero result invalidates
// output. Status 4 means invalid geometry or buffer shape; component status
// 3/4 means nonfinite data and 7 means cancellation.
pub fn render_f64(input: []const f64, width: usize, height: usize,
    recipe: photo_geometry.Recipe, rotated: []f64, output: []f64,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not photo_geometry.valid(recipe, width, height) or
    input.len() != width * height * 3 or
    output.len() != recipe.crop.width * recipe.crop.height * 3 {
        return 4;
    }
    if recipe.straighten.angle_radians == 0.0 {
        return crop.apply_f64(input, width, height, recipe.crop,
            output, cancelled, context
        ) as i32;
    }
    if rotated.len() != input.len() {
        return 4;
    }
    const status = straighten.apply_f64(input, width, height,
        recipe.straighten, rotated, cancelled, context
    );
    if status != 0 {
        return status as i32;
    }
    return crop.apply_f64(rotated, width, height, recipe.crop,
        output, cancelled, context
    ) as i32;
}

// V2 selects the transformed crop directly. Quarter turns and mirrors need
// no full-size orientation scratch; straighten still uses caller scratch.
pub fn render_f64_v2(input: []const f64, width: usize, height: usize,
    recipe: photo_geometry.RecipeV2, rotated: []f64, output: []f64,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not photo_geometry.valid_v2(recipe, width, height) or
    input.len() != width * height * 3 or
    output.len() != recipe.crop.width * recipe.crop.height * 3 {
        return 4;
    }
    if recipe.straighten.angle_radians == 0.0 {
        return orthogonal_transform.apply_region_f64(input, width, height,
            recipe.transform, recipe.crop.left, recipe.crop.top,
            recipe.crop.width, recipe.crop.height, output, cancelled, context
        ) as i32;
    }
    if rotated.len() != input.len() {
        return 4;
    }
    const status = straighten.apply_f64(input, width, height,
        recipe.straighten, rotated, cancelled, context
    );
    if status != 0 {
        return status as i32;
    }
    return orthogonal_transform.apply_region_f64(rotated, width, height,
        recipe.transform, recipe.crop.left, recipe.crop.top,
        recipe.crop.width, recipe.crop.height, output, cancelled, context
    ) as i32;
}

pub fn render_tiff_v2(input: []const f64, width: usize, height: usize,
    recipe: photo_geometry.RecipeV2, rotated: []f64, cropped: []f64,
    rgb16: []u16, icc: []const u8, tiff: []u8,
    baseline_exposure_ev: f64, controls: preview_develop_plan.Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not photo_geometry.valid_v2(recipe, width, height) {
        return 4;
    }
    if not preview_develop_plan.valid(controls) {
        return 5;
    }
    const output_width = recipe.crop.width;
    const output_height = recipe.crop.height;
    const plan = rgb16_writer.layout(output_width, output_height, icc.len());
    if plan.status != 0 {
        return plan.status;
    }
    if rgb16.len() != output_width * output_height * 3 or
    tiff.len() != plan.total_bytes {
        return 4;
    }
    const geometry_status = render_f64_v2(input, width, height, recipe,
        rotated, cropped, cancelled, context
    );
    if geometry_status != 0 {
        return geometry_status;
    }
    const render_status = preview_develop_plan.render_rgb16(cropped.ptr,
        cropped.len(), rgb16.ptr, rgb16.len(), output_width, output_height,
        baseline_exposure_ev, controls, cancelled, context
    );
    if render_status != 0 {
        return render_status;
    }
    return rgb16_writer.encode(rgb16, output_width, output_height, icc,
        tiff, cancelled, context
    );
}

pub fn render_preview_v2(input: []const f64, width: usize, height: usize,
    recipe: photo_geometry.RecipeV2, rotated: []f64, cropped: []f64,
    fitted: []f64, output: []u8, preview_width: usize,
    preview_height: usize, baseline_exposure_ev: f64,
    controls: preview_develop_plan.Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not photo_geometry.valid_v2(recipe, width, height) or
    preview_width == 0 or preview_height == 0 or
    preview_width > 2048 or preview_height > 2048 or
    preview_width > recipe.crop.width or
    preview_height > recipe.crop.height or
    preview_width > 4194304 / preview_height or
    fitted.len() != preview_width * preview_height * 3 or
    output.len() != preview_width * preview_height * 4 {
        return 4;
    }
    if not preview_develop_plan.valid(controls) {
        return 5;
    }
    const geometry_status = render_f64_v2(input, width, height, recipe,
        rotated, cropped, cancelled, context
    );
    if geometry_status != 0 {
        return geometry_status;
    }
    const reduce_status = working_rgb_resample.reduce(cropped,
        recipe.crop.width, recipe.crop.height, fitted, preview_width,
        preview_height, cancelled, context
    );
    if reduce_status != 0 {
        return reduce_status;
    }
    return preview_develop_plan.render(fitted.ptr, fitted.len(), output.ptr,
        output.len(), preview_width, preview_height, baseline_exposure_ev,
        controls, cancelled, context
    );
}

// Develop and encode an upright full-size working frame after geometry.
// The recipe is applied before spatial detail controls, so their radii are
// measured in output pixels. All scratch and output buffers are caller-owned.
// A nonzero result invalidates the TIFF buffer.
pub fn render_tiff(input: []const f64, width: usize, height: usize,
    recipe: photo_geometry.Recipe, rotated: []f64, cropped: []f64,
    rgb16: []u16, icc: []const u8, tiff: []u8,
    baseline_exposure_ev: f64, controls: preview_develop_plan.Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not photo_geometry.valid(recipe, width, height) {
        return 4;
    }
    if not preview_develop_plan.valid(controls) {
        return 5;
    }
    const output_width = recipe.crop.width;
    const output_height = recipe.crop.height;
    const plan = rgb16_writer.layout(output_width, output_height, icc.len());
    if plan.status != 0 {
        return plan.status;
    }
    if rgb16.len() != output_width * output_height * 3 or
    tiff.len() != plan.total_bytes {
        return 4;
    }
    const geometry_status = render_f64(input, width, height, recipe,
        rotated, cropped, cancelled, context
    );
    if geometry_status != 0 {
        return geometry_status;
    }
    const render_status = preview_develop_plan.render_rgb16(cropped.ptr,
        cropped.len(), rgb16.ptr, rgb16.len(), output_width, output_height,
        baseline_exposure_ev, controls, cancelled, context
    );
    if render_status != 0 {
        return render_status;
    }
    return rgb16_writer.encode(rgb16, output_width, output_height, icc,
        tiff, cancelled, context
    );
}

// Fitted RGBA8 from the same full-size upright geometry recipe as TIFF export.
// The selected scene-linear frame is area-reduced before develop controls.
// The caller owns disjoint rotated, cropped, fitted and output buffers.
// A nonzero result invalidates fitted and output.
pub fn render_preview(input: []const f64, width: usize, height: usize,
    recipe: photo_geometry.Recipe, rotated: []f64, cropped: []f64,
    fitted: []f64, output: []u8, preview_width: usize,
    preview_height: usize, baseline_exposure_ev: f64,
    controls: preview_develop_plan.Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not photo_geometry.valid(recipe, width, height) or
    preview_width == 0 or preview_height == 0 or
    preview_width > 2048 or preview_height > 2048 or
    preview_width > recipe.crop.width or
    preview_height > recipe.crop.height or
    preview_width > 4194304 / preview_height or
    fitted.len() != preview_width * preview_height * 3 or
    output.len() != preview_width * preview_height * 4 {
        return 4;
    }
    if not preview_develop_plan.valid(controls) {
        return 5;
    }
    const geometry_status = render_f64(input, width, height, recipe,
        rotated, cropped, cancelled, context
    );
    if geometry_status != 0 {
        return geometry_status;
    }
    const reduce_status = working_rgb_resample.reduce(cropped,
        recipe.crop.width, recipe.crop.height, fitted, preview_width,
        preview_height, cancelled, context
    );
    if reduce_status != 0 {
        return reduce_status;
    }
    return preview_develop_plan.render(fitted.ptr, fitted.len(), output.ptr,
        output.len(), preview_width, preview_height, baseline_exposure_ev,
        controls, cancelled, context
    );
}
