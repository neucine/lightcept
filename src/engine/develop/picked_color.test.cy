import .engine.develop.picked_color;

fn no_cancel(context: usize): bool {
    return false;
}

test "picked color selects only the chosen hue" {
    var edit = picked_color.neutral();
    edit.enabled = true;
    edit.center_degrees = 0;
    edit.half_width_degrees = 20;
    edit.softness_percent = 50;
    edit.saturation_percent = -50;
    const input: [9]f64 = [0.6, 0.1, 0.1, 0.1, 0.6, 0.1,
        0.2, 0.2, 0.2
    ];
    var output: [9]f64 = [0.0] ** 9;
    assert(picked_color.apply_f64(input[0..], 3, 1, edit,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] != input[0]);
    assert(output[3] == input[3] and output[4] == input[4] and
        output[5] == input[5]
    );
    assert(output[6] == input[6] and output[7] == input[7] and
        output[8] == input[8]
    );
}

test "picked color range wraps and feathers" {
    var edit = picked_color.neutral();
    edit.enabled = true;
    edit.center_degrees = 350;
    edit.half_width_degrees = 30;
    edit.softness_percent = 50;
    assert(picked_color.weight(0.6, 0.1, 0.1, edit) > 0.0);
    assert(picked_color.weight(0.6, 0.45, 0.1, edit) == 0.0);
}

test "photo picker uses selection hue for dark saturated pixels" {
    const hue = picked_color.sample_hue(0.08, 0.07, 0.005);
    assert(hue >= 0 and hue < 90);
    assert(picked_color.sample_hue(0.04, 0.04, 0.04) == -1);
    var edit = picked_color.neutral();
    edit.enabled = true;
    edit.center_degrees = hue;
    edit.half_width_degrees = 20;
    edit.softness_percent = 50;
    assert(picked_color.weight(0.08, 0.07, 0.005, edit) > 0.0);
}
