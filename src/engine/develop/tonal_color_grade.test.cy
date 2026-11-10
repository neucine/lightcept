import .engine.develop.tonal_color_grade;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "neutral grading preserves scene-linear samples" {
    const input: [6]f64 = [0.12, 0.18, 0.25, 1.0, 0.5, 0.2];
    var output: [6]f64 = [0.0] ** 6;
    const edit = tonal_color_grade.neutral();
    assert(tonal_color_grade.valid(edit));
    assert(not tonal_color_grade.nonneutral(edit));
    assert(tonal_color_grade.apply_f64(input[0..], 2, 1, edit,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output == input);
}

test "shadow tint preserves luminance and fades toward highlights" {
    var edit = tonal_color_grade.neutral();
    edit.wheels[0] = {
        hue_degrees: 0,
        strength_percent: 50,
        luminance_percent: 0
    };
    const input: [6]f64 = [0.05, 0.05, 0.05, 2.0, 2.0, 2.0];
    var output: [6]f64 = [0.0] ** 6;
    assert(tonal_color_grade.apply_f64(input[0..], 2, 1, edit,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > output[1] and output[1] == output[2]);
    assert(output[0] - output[2] > output[3] - output[5]);
    const luminance = 0.2627 * output[0] + 0.6780 * output[1] +
    0.0593 * output[2];
    assert(luminance > 0.049999 and luminance < 0.050001);
}

test "grading preserves black and positive balance favors highlights" {
    var edit = tonal_color_grade.neutral();
    edit.wheels[0] = {
        hue_degrees: 0,
        strength_percent: 50,
        luminance_percent: 0
    };
    const input: [6]f64 = [0.0, 0.0, 0.0, 0.18, 0.18, 0.18];
    var shadow_balance: [6]f64 = [0.0] ** 6;
    var highlight_balance: [6]f64 = [0.0] ** 6;
    edit.balance_percent = -100;
    assert(tonal_color_grade.apply_f64(input[0..], 2, 1, edit,
        shadow_balance[0..], no_cancel, 0
    ) == 0);
    edit.balance_percent = 100;
    assert(tonal_color_grade.apply_f64(input[0..], 2, 1, edit,
        highlight_balance[0..], no_cancel, 0
    ) == 0);
    assert(shadow_balance[0] == 0.0 and shadow_balance[1] == 0.0 and
        shadow_balance[2] == 0.0
    );
    assert(highlight_balance[0] == 0.0 and highlight_balance[1] == 0.0 and
        highlight_balance[2] == 0.0
    );
    assert(shadow_balance[3] - shadow_balance[5] >
        highlight_balance[3] - highlight_balance[5]
    );
}

test "grading rejects invalid values and cancellation" {
    var edit = tonal_color_grade.neutral();
    edit.wheels[2] = {
        hue_degrees: 360,
        strength_percent: 0,
        luminance_percent: 0
    };
    assert(not tonal_color_grade.valid(edit));
    const input: [3]f64 = [0.2, 0.2, 0.2];
    var output: [3]f64 = [0.0] ** 3;
    assert(tonal_color_grade.apply_f64(input[0..], 1, 1, edit,
        output[0..], no_cancel, 0
    ) == 1);
    edit = tonal_color_grade.neutral();
    assert(tonal_color_grade.apply_f64(input[0..], 1, 1, edit,
        output[0..], cancel, 0
    ) == 7);
}
