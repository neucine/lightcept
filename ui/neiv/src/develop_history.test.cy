import .develop_history;
import lightcept_core.engine.pipeline.preview_develop_plan;

test "develop history branches after undo and keeps bounded recent states" {
    var history = develop_history.empty();
    develop_history.reset(&history);
    assert(not develop_history.can_undo(&history));
    var first = develop_history.neutral();
    first.exposure_tenths = 5;
    develop_history.append(&history, first);
    var second = first;
    second.contrast_percent = 20;
    develop_history.append(&history, second);
    assert(history.length == 3);
    history.cursor = 1;
    assert(develop_history.can_redo(&history));
    var branch = first;
    branch.shadows_percent = 30;
    develop_history.append(&history, branch);
    assert(history.length == 3);
    assert(not develop_history.can_redo(&history));
    assert(history.entries[2].shadows_percent == 30);
    var index: i32 = 0;
    while index < 40 {
        var next = branch;
        next.contrast_percent = index;
        develop_history.append(&history, next);
        index = index + 1;
    }
    assert(history.length == 32);
    assert(history.cursor == 31);
    assert(history.entries[31].contrast_percent == 39);
    assert(history.entries[0].contrast_percent == 0);
    assert(develop_history.valid(&history));
}

fn controls(values: develop_history.Values): preview_develop_plan.Controls {
    return {
        exposure_tenths: values.exposure_tenths,
        contrast_percent: values.contrast_percent,
        shadows_percent: values.shadows_percent,
        highlights_percent: values.highlights_percent,
        blacks_percent: values.blacks_percent,
        whites_percent: values.whites_percent,
        warmth_percent: values.warmth_percent,
        tint_percent: values.tint_percent,
        vibrance_percent: values.vibrance_percent,
        saturation_percent: values.saturation_percent,
        clarity_percent: values.clarity_percent,
        texture_percent: values.texture_percent
    };
}

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

test "undo target replays exact shared develop preview bytes" {
    const working: [9]f64 = [0.02, 0.04, 0.08, 0.35, 0.25, 0.15, 0.75, 0.65, 0.55];
    var history = develop_history.empty();
    develop_history.reset(&history);
    var exposure = develop_history.neutral();
    exposure.exposure_tenths = 5;
    develop_history.append(&history, exposure);
    var contrast = exposure;
    contrast.saturation_percent = 30;
    develop_history.append(&history, contrast);
    var first: [12]u8 = [0] ** 12;
    var changed: [12]u8 = [0] ** 12;
    var replay: [12]u8 = [0] ** 12;
    assert(preview_develop_plan.render(working[0..].ptr, 9, first[0..].ptr, 12, 3, 1, 0.0, controls(history.entries[1]), no_cancel, 0) == 0);
    assert(preview_develop_plan.render(working[0..].ptr, 9, changed[0..].ptr, 12, 3, 1, 0.0, controls(history.entries[2]), no_cancel, 0) == 0);
    history.cursor = 1;
    assert(preview_develop_plan.render(working[0..].ptr, 9, replay[0..].ptr, 12, 3, 1, 0.0, controls(history.entries[history.cursor]), no_cancel, 0) == 0);
    var index: usize = 0;
    var differs = false;
    while index < 12 {
        assert(replay[index] == first[index]);
        if changed[index] != first[index] {
            differs = true;
        }
        index = index + 1;
    }
    assert(differs);
}

test "saved history rejects invalid controls and nonneutral source state" {
    var history = develop_history.empty();
    assert(not develop_history.valid(&history));
    develop_history.reset(&history);
    assert(develop_history.valid(&history));
    var baseline = history.entries[0];
    baseline.exposure_tenths = 1;
    history.entries[0] = baseline;
    assert(not develop_history.valid(&history));
    history.entries[0] = develop_history.neutral();
    var edit = develop_history.neutral();
    edit.whites_percent = 101;
    develop_history.append(&history, edit);
    assert(not develop_history.valid(&history));
    edit.whites_percent = 100;
    history.entries[1] = edit;
    assert(develop_history.valid(&history));
    edit.saturation_percent = 101;
    history.entries[1] = edit;
    assert(not develop_history.valid(&history));
    edit.saturation_percent = -100;
    history.entries[1] = edit;
    assert(develop_history.valid(&history));
    edit.texture_percent = 101;
    history.entries[1] = edit;
    assert(not develop_history.valid(&history));
    edit.texture_percent = -100;
    history.entries[1] = edit;
    assert(develop_history.valid(&history));
    history.cursor = 2;
    assert(not develop_history.valid(&history));
}

test "HSL bands travel with history and reject invalid project values" {
    var history = develop_history.empty();
    develop_history.reset(&history);
    var color = develop_history.neutral();
    if develop_history.with_hsl_percent(color.hsl, 1, 2, 35) is changed {
        color.hsl = changed;
    } else {
        assert(false);
    }
    develop_history.append(&history, color);
    assert(develop_history.valid(&history));
    var exposure = color;
    exposure.exposure_tenths = 5;
    develop_history.append(&history, exposure);
    assert(develop_history.hsl_percent(history.entries[2].hsl, 1, 2) == 35);
    history.cursor = 1;
    assert(develop_history.hsl_percent(history.entries[history.cursor].hsl, 1, 2) == 35);
    var invalid = history.entries[1];
    invalid.hsl.words[0] = 0xffffffffffffffff;
    history.entries[1] = invalid;
    assert(not develop_history.valid(&history));
    history.entries[1] = color;
    var invalid_source = history.entries[0];
    if develop_history.with_hsl_percent(invalid_source.hsl, 2, 7, 1) is changed {
        invalid_source.hsl = changed;
    } else {
        assert(false);
    }
    history.entries[0] = invalid_source;
    assert(not develop_history.valid(&history));
}

test "geometry travels with a develop history snapshot" {
    var history = develop_history.empty();
    develop_history.reset(&history);
    var cropped = develop_history.neutral();
    cropped.crop_left = 200;
    cropped.crop_top = 100;
    cropped.crop_width = 4000;
    cropped.crop_height = 3000;
    cropped.straighten_millidegrees = 1250;
    develop_history.append(&history, cropped);
    assert(develop_history.valid(&history));
    const recipe = develop_history.geometry(cropped, 6000, 4000);
    if recipe is value {
        assert(value.crop.left == 200 and value.crop.width == 4000 and
            value.straighten.angle_radians > 0.021
        );
    } else {
        assert(false);
    }
    history.cursor = 0;
    assert(history.entries[history.cursor].crop_width == 0);
    history.cursor = 1;
    assert(history.entries[history.cursor].crop_left == 200);
    var invalid = history.entries[1];
    invalid.crop_width = 0;
    history.entries[1] = invalid;
    assert(not develop_history.valid(&history));
}

test "quarter turn history validates crop in transformed canvas" {
    var history = develop_history.empty();
    develop_history.reset(&history);
    var turned = develop_history.neutral();
    turned.transform_code = 6;
    turned.crop_left = 3000;
    turned.crop_top = 100;
    turned.crop_width = 900;
    turned.crop_height = 5000;
    develop_history.append(&history, turned);
    assert(develop_history.valid(&history));
    var accepted = false;
    if develop_history.geometry_v2(turned, 6000, 4000) is recipe {
        accepted = recipe.crop.width == 900;
    }
    assert(accepted);
    turned.crop_width = 1001;
    var rejected = true;
    if develop_history.geometry_v2(turned, 6000, 4000) is recipe {
        rejected = false;
    }
    assert(rejected);
    turned.transform_code = 9;
    history.entries[1] = turned;
    assert(not develop_history.valid(&history));
}

test "luma curve point is an undoable bounded history value" {
    var history = develop_history.empty();
    develop_history.reset(&history);
    const neutral = develop_history.neutral_curve();
    assert(neutral[9] == 250 and neutral[10] == 500 and neutral[11] == 750);
    if develop_history.with_curve_point(neutral, 3, 1, 600) is changed {
        assert(changed[10] == 600 and develop_history.valid_curve(changed));
        var edit = develop_history.neutral();
        edit.curve = changed;
        develop_history.append(&history, edit);
        assert(history.entries[1].curve[10] == 600);
        history.cursor = 0;
        assert(history.entries[history.cursor].curve[10] == 500);
    } else {
        assert(false);
    }
    var rejected = true;
    if develop_history.with_curve_point(neutral, 3, 1, 900) is accepted {
        rejected = false;
    }
    assert(rejected);
}
