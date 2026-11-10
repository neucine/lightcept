import .engine.pipeline.photo_geometry_pipeline;
import .engine.develop.photo_geometry;
import .engine.pipeline.preview_develop_plan;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

test "full-resolution geometry crops after a scene-linear straighten" {
    const input: [27]f64 = [
        0.0, 0.0, 0.5, 1.0, 0.0, 0.5, 2.0, 0.0, 0.5,
        0.0, 1.0, 0.5, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5,
        0.0, 2.0, 0.5, 1.0, 2.0, 0.5, 2.0, 2.0, 0.5
    ];
    var rotated: [27]f64 = [9.0] ** 27;
    var output: [3]f64 = [9.0] ** 3;
    var recipe = photo_geometry.neutral(3, 3);
    var crop = recipe.crop;
    crop.left = 1;
    crop.top = 1;
    crop.width = 1;
    crop.height = 1;
    recipe.crop = crop;
    var straighten = recipe.straighten;
    straighten.angle_radians = 0.2;
    recipe.straighten = straighten;
    assert(photo_geometry_pipeline.render_f64(input[0..], 3, 3,
        recipe, rotated[0..], output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 1.0 and output[1] == 1.0 and output[2] == 0.5);
    straighten.angle_radians = 0.0;
    recipe.straighten = straighten;
    var no_scratch: [1]f64 = [0.0];
    assert(photo_geometry_pipeline.render_f64(input[0..], 3, 3,
        recipe, no_scratch[0..0], output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[12] and output[2] == input[14]);
}

test "cropped working frame sets TIFF extent and develops selected pixels" {
    const input: [12]f64 = [0.2, 0.2, 0.2, 0.4, 0.4, 0.4,
        0.6, 0.6, 0.6, 0.8, 0.8, 0.8
    ];
    var recipe = photo_geometry.neutral(2, 2);
    var crop = recipe.crop;
    crop.left = 1;
    crop.top = 0;
    crop.width = 1;
    recipe.crop = crop;
    var no_scratch: [1]f64 = [0.0];
    var cropped: [6]f64 = [0.0] ** 6;
    var rgb16: [6]u16 = [0] ** 6;
    var icc: [128]u8 = [0] ** 128;
    icc[36] = 97;
    icc[37] = 99;
    icc[38] = 115;
    icc[39] = 112;
    var tiff: [304]u8 = [0] ** 304;
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: 0,
        contrast_percent: 0,
        shadows_percent: 0,
        highlights_percent: 0,
        blacks_percent: 0,
        whites_percent: 0,
        warmth_percent: 0,
        tint_percent: 0,
        vibrance_percent: 0,
        saturation_percent: 0,
        clarity_percent: 0,
        texture_percent: 0
    };
    assert(photo_geometry_pipeline.render_tiff(input[0..], 2, 2, recipe,
        no_scratch[0..0], cropped[0..], rgb16[0..], icc[0..], tiff[0..],
        0.0, controls, no_cancel, 0
    ) == 0);
    assert(cropped[0] == 0.4 and cropped[3] == 0.8);
    assert(tiff[18] == 1 and tiff[30] == 2);
    assert(tiff[292] != tiff[298]);
}

test "fitted preview reduces the selected source rectangle before developing" {
    const input: [24]f64 = [
        0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0, 3.0, 3.0, 3.0,
        4.0, 4.0, 4.0, 5.0, 5.0, 5.0, 6.0, 6.0, 6.0, 7.0, 7.0, 7.0
    ];
    var recipe = photo_geometry.neutral(4, 2);
    var crop = recipe.crop;
    crop.left = 1;
    crop.width = 2;
    recipe.crop = crop;
    var no_scratch: [1]f64 = [0.0];
    var cropped: [12]f64 = [0.0] ** 12;
    var fitted: [3]f64 = [0.0] ** 3;
    var output: [4]u8 = [0] ** 4;
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: 0,
        contrast_percent: 0,
        shadows_percent: 0,
        highlights_percent: 0,
        blacks_percent: 0,
        whites_percent: 0,
        warmth_percent: 0,
        tint_percent: 0,
        vibrance_percent: 0,
        saturation_percent: 0,
        clarity_percent: 0,
        texture_percent: 0
    };
    assert(photo_geometry_pipeline.render_preview(input[0..], 4, 2,
        recipe, no_scratch[0..0], cropped[0..], fitted[0..], output[0..],
        1, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(cropped[0] == 1.0 and cropped[9] == 6.0);
    assert(fitted[0] == 3.5 and fitted[1] == 3.5 and fitted[2] == 3.5);
    assert(output[3] == 255);
}

test "v2 quarter turn selects cropped pixels for preview and TIFF" {
    const input: [18]f64 = [
        0.0, 0.0, 0.0, 0.2, 0.2, 0.2, 0.4, 0.4, 0.4,
        0.6, 0.6, 0.6, 0.8, 0.8, 0.8, 1.0, 1.0, 1.0
    ];
    const neutral = photo_geometry.neutral(3, 2);
    const recipe: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: neutral.straighten,
        transform: {
            version: 1,
            code: 6
        },
        crop: {
            version: 1,
            left: 1,
            top: 1,
            width: 1,
            height: 2
        }
    };
    assert(photo_geometry.valid_v2(recipe, 3, 2));
    const mapped = photo_geometry.map_source_point_v2(recipe,
        3, 2, 1.0, 0.0
    );
    assert(mapped.inside and mapped.x == 0.0 and mapped.y == 0.0);
    var no_scratch: [1]f64 = [0.0];
    var cropped: [6]f64 = [99.0] ** 6;
    assert(photo_geometry_pipeline.render_f64_v2(input[0..], 3, 2,
        recipe, no_scratch[0..0], cropped[0..], no_cancel, 0
    ) == 0);
    assert(cropped[0] == 0.2 and cropped[3] == 0.4);
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: 0,
        contrast_percent: 0,
        shadows_percent: 0,
        highlights_percent: 0,
        blacks_percent: 0,
        whites_percent: 0,
        warmth_percent: 0,
        tint_percent: 0,
        vibrance_percent: 0,
        saturation_percent: 0,
        clarity_percent: 0,
        texture_percent: 0
    };
    var fitted: [3]f64 = [99.0] ** 3;
    var preview: [4]u8 = [0] ** 4;
    assert(photo_geometry_pipeline.render_preview_v2(input[0..], 3, 2,
        recipe, no_scratch[0..0], cropped[0..], fitted[0..], preview[0..],
        1, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(fitted[0] > 0.299 and fitted[0] < 0.301 and preview[3] == 255);
    var rgb16: [6]u16 = [0] ** 6;
    var icc: [128]u8 = [0] ** 128;
    icc[36] = 97;
    icc[37] = 99;
    icc[38] = 115;
    icc[39] = 112;
    var tiff: [304]u8 = [0] ** 304;
    assert(photo_geometry_pipeline.render_tiff_v2(input[0..], 3, 2,
        recipe, no_scratch[0..0], cropped[0..], rgb16[0..], icc[0..],
        tiff[0..], 0.0, controls, no_cancel, 0
    ) == 0);
    assert(tiff[18] == 1 and tiff[30] == 2);
    assert(rgb16[0] < rgb16[3]);
}
