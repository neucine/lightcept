import .engine.pipeline.preview_develop_plan;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.develop.hsl_grading;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

test "eight band HSL uses one scene stage for preview and RGB16" {
    const working: [12]f64 = [0.8, 0.2, 0.1, 0.1, 0.6, 0.2,
        0.2, 0.1, 0.7, 0.18, 0.18, 0.18
    ];
    var bands: [8]hsl_grading.GradeNode = [hsl_grading.neutral_node()] ** 8;
    var index: usize = 0;
    while index < 8 {
        bands[index] = {
            hue_degrees: 0.0,
            chroma_gain: 0.7,
            luminance_ev: 0.0
        };
        index = index + 1;
    }
    const expanded = hsl_grading.eight_band_nodes(bands);
    assert(expanded.valid);
    const asset: hsl_grading.GradeAsset = {
        version: 1,
        nodes: expanded.nodes[..]
    };
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
    var scratch_preview: [12]f64 = [0.0] ** 12;
    var scratch_export: [12]f64 = [0.0] ** 12;
    var preview: [16]u8 = [0] ** 16;
    var neutral: [16]u8 = [0] ** 16;
    var rgb16: [12]u16 = [0] ** 12;
    assert(preview_develop_plan.render(working[0..].ptr, 12,
        neutral[0..].ptr, 16, 2, 2, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(preview_develop_plan.render_with_hsl(working[0..],
        scratch_preview[0..], preview[0..], 2, 2, 0.0,
        controls, &asset, no_cancel, 0
    ) == 0);
    assert(preview_develop_plan.render_rgb16_with_hsl(working[0..],
        scratch_export[0..], rgb16[0..], 2, 2, 0.0,
        controls, &asset, no_cancel, 0
    ) == 0);
    assert(preview[0] != neutral[0]);
    index = 0;
    while index < 4 {
        var channel: usize = 0;
        while channel < 3 {
            const coarse = preview[index * 4 + channel] as i32;
            const fine = (rgb16[index * 3 + channel] / 257) as i32;
            assert(fine >= coarse - 1 and fine <= coarse + 1);
            channel = channel + 1;
        }
        index = index + 1;
    }
}

test "saved develop controls share preview and RGB16 export stages" {
    const working: [36]f64 = [0.12, 0.18, 0.25] ** 12;
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: 5,
        contrast_percent: 10,
        shadows_percent: 10,
        highlights_percent: -10,
        blacks_percent: -10,
        whites_percent: 10,
        warmth_percent: 10,
        tint_percent: -10,
        vibrance_percent: 10,
        saturation_percent: 10,
        clarity_percent: -10,
        texture_percent: 10
    };
    var preview: [48]u8 = [0] ** 48;
    var export_rgb: [36]u16 = [0] ** 36;
    assert(preview_develop_plan.render(working[0..].ptr, 36, preview[0..].ptr,
        48, 3, 4, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(preview_develop_plan.render_rgb16(working[0..].ptr, 36,
        export_rgb[0..].ptr, 36, 3, 4, 0.0, controls, no_cancel, 0
    ) == 0);
    var pixel: usize = 0;
    while pixel < 12 {
        var channel: usize = 0;
        while channel < 3 {
            const coarse = preview[pixel * 4 + channel] as i32;
            const fine = (export_rgb[pixel * 3 + channel] / 257) as i32;
            assert(fine >= coarse - 1 and fine <= coarse + 1);
            channel = channel + 1;
        }
        pixel = pixel + 1;
    }
}

test "shared preview controls preserve neutral bytes and reject invalid percentages before writes" {
    const working: [9]f64 = [0.02, 0.02, 0.02, 0.35, 0.35, 0.35, 0.75, 0.75, 0.75];
    const neutral: preview_develop_plan.Controls = {
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
    var reference: [12]u8 = [0] ** 12;
    var actual: [12]u8 = [0] ** 12;
    assert(spatial_camera_pipeline.render_prepared_tone(working[0..].ptr, 9, reference[0..].ptr, 12, 3, 1, 0.0, 0.0, 1.0, 0.0, 0.0, no_cancel, 0) == 0);
    assert(preview_develop_plan.render(working[0..].ptr, 9, actual[0..].ptr, 12, 3, 1, 0.0, neutral, no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 12 {
        assert(actual[index] == reference[index]);
        index = index + 1;
    }
    var changed = neutral;
    changed.blacks_percent = 100;
    assert(preview_develop_plan.render(working[0..].ptr, 9, actual[0..].ptr, 12, 3, 1, 0.0, changed, no_cancel, 0) == 0);
    assert(actual[0] < reference[0]);
    changed.blacks_percent = 0;
    changed.whites_percent = 100;
    assert(preview_develop_plan.render(working[0..].ptr, 9, actual[0..].ptr, 12, 3, 1, 0.0, changed, no_cancel, 0) == 0);
    assert(actual[8] > reference[8]);
    actual[0] = 19;
    changed.whites_percent = 101;
    assert(preview_develop_plan.render(working[0..].ptr, 9, actual[0..].ptr, 12, 3, 1, 0.0, changed, no_cancel, 0) == 5 and actual[0] == 19);
    assert(preview_develop_plan.white_strength(-100) == -0.5);
    assert(preview_develop_plan.white_strength(100) == 1.0);
}

test "relative color controls change rendered channels and keep the neutral route exact" {
    const working: [3]f64 = [0.25, 0.35, 0.45];
    var controls: preview_develop_plan.Controls = {
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
    var neutral: [4]u8 = [0] ** 4;
    var adjusted: [4]u8 = [0] ** 4;
    assert(preview_develop_plan.render(working[0..].ptr, 3, neutral[0..].ptr, 4, 1, 1, 0.0, controls, no_cancel, 0) == 0);
    controls.warmth_percent = 40;
    assert(preview_develop_plan.render(working[0..].ptr, 3, adjusted[0..].ptr, 4, 1, 1, 0.0, controls, no_cancel, 0) == 0);
    assert(adjusted[0] > neutral[0] and adjusted[2] < neutral[2]);
    controls.warmth_percent = 0;
    controls.tint_percent = 40;
    assert(preview_develop_plan.render(working[0..].ptr, 3, adjusted[0..].ptr, 4, 1, 1, 0.0, controls, no_cancel, 0) == 0);
    assert(adjusted[1] < neutral[1]);
    controls.tint_percent = 0;
    controls.vibrance_percent = 70;
    assert(preview_develop_plan.render(working[0..].ptr, 3, adjusted[0..].ptr, 4, 1, 1, 0.0, controls, no_cancel, 0) == 0);
    assert(adjusted[0] != neutral[0] or adjusted[2] != neutral[2]);
}

test "saturation reaches monochrome and changes all colors from neutral" {
    const working: [3]f64 = [0.65, 0.30, 0.10];
    var controls: preview_develop_plan.Controls = {
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
    var neutral: [4]u8 = [0] ** 4;
    var changed: [4]u8 = [0] ** 4;
    assert(preview_develop_plan.render(working[0..].ptr, 3, neutral[0..].ptr, 4,
        1, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    controls.saturation_percent = -100;
    assert(preview_develop_plan.render(working[0..].ptr, 3, changed[0..].ptr, 4,
        1, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(changed[0] == changed[1] and changed[1] == changed[2]);
    controls.saturation_percent = 100;
    assert(preview_develop_plan.render(working[0..].ptr, 3, changed[0..].ptr, 4,
        1, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(changed[0] > neutral[0] and changed[2] < neutral[2]);
    controls.saturation_percent = 101;
    changed[0] = 91;
    assert(preview_develop_plan.render(working[0..].ptr, 3, changed[0..].ptr, 4,
        1, 1, 0.0, controls, no_cancel, 0
    ) == 5 and changed[0] == 91);
}

test "clarity changes midscale detail and neutral clarity retains exact color bytes" {
    var working: [33]f64 = [0.2] ** 33;
    var x: usize = 4;
    while x <= 6 {
        working[x * 3] = 0.4;
        working[x * 3 + 1] = 0.4;
        working[x * 3 + 2] = 0.4;
        x = x + 1;
    }
    var controls: preview_develop_plan.Controls = {
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
    var neutral: [44]u8 = [0] ** 44;
    var changed: [44]u8 = [0] ** 44;
    assert(preview_develop_plan.render(working[0..].ptr, 33, neutral[0..].ptr, 44,
        11, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    controls.clarity_percent = 100;
    assert(preview_develop_plan.render(working[0..].ptr, 33, changed[0..].ptr, 44,
        11, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    var differs = false;
    x = 0;
    while x < 44 {
        if neutral[x] != changed[x] {
            differs = true;
        }
        x = x + 1;
    }
    assert(differs);
    controls.clarity_percent = 101;
    changed[0] = 91;
    assert(preview_develop_plan.render(working[0..].ptr, 33, changed[0..].ptr, 44,
        11, 1, 0.0, controls, no_cancel, 0
    ) == 5 and changed[0] == 91);
}

test "texture changes fine detail and zero preserves the pinned clarity preview" {
    var working: [27]f64 = [0.2] ** 27;
    working[3] = 0.24;
    working[4] = 0.24;
    working[5] = 0.24;
    var pixel: usize = 5;
    while pixel < 9 {
        working[pixel * 3] = 1.0;
        working[pixel * 3 + 1] = 1.0;
        working[pixel * 3 + 2] = 1.0;
        pixel = pixel + 1;
    }
    var controls: preview_develop_plan.Controls = {
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
    var neutral: [36]u8 = [0] ** 36;
    var textured: [36]u8 = [0] ** 36;
    assert(preview_develop_plan.render(working[0..].ptr, 27, neutral[0..].ptr, 36,
        9, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    controls.texture_percent = 100;
    assert(preview_develop_plan.render(working[0..].ptr, 27, textured[0..].ptr, 36,
        9, 1, 0.0, controls, no_cancel, 0
    ) == 0);
    assert(textured[4] > neutral[4]);
    assert(textured[20] == neutral[20]);
    controls.texture_percent = 101;
    textured[0] = 91;
    assert(preview_develop_plan.render(working[0..].ptr, 27, textured[0..].ptr, 36,
        9, 1, 0.0, controls, no_cancel, 0
    ) == 5 and textured[0] == 91);
}
