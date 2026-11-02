import .engine.analysis.auto_white_balance;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "gray-world proposal neutralizes a varied tinted-neutral tile" {
    var input: [48]f32 = [0.0] ** 48;
    var pixel: usize = 0;
    while pixel < 16 {
        const level = 0.25 + (pixel as f64) / 64.0;
        input[pixel * 3] = (level * 1.5) as f32;
        input[pixel * 3 + 1] = level as f32;
        input[pixel * 3 + 2] = level as f32;
        pixel = pixel + 1;
    }
    const proposed = auto_white_balance.propose(input[0..], 4, 4,
        71, no_cancel, 0
    );
    assert(proposed.status == 0 and proposed.version == 1);
    assert(proposed.camera_matrix_hash == 71);
    assert(proposed.eligible_pixels == 16 and proposed.total_pixels == 16);
    assert(proposed.working_gains[0] < 1.0);
    assert(proposed.working_gains[1] > 1.0);
    const corrected_red = proposed.mean_rgb[0] * proposed.working_gains[0];
    const corrected_green = proposed.mean_rgb[1] * proposed.working_gains[1];
    assert(corrected_red > corrected_green - 0.00001
        and corrected_red < corrected_green + 0.00001
    );
}

test "gray-world excludes clipped highlights and returns no weak proposal" {
    var input: [51]f32 = [0.3] ** 51;
    input[48] = 1.5;
    input[49] = 1.5;
    input[50] = 1.5;
    const proposed = auto_white_balance.propose(input[0..], 17, 1,
        4, no_cancel, 0
    );
    assert(proposed.status == 0 and proposed.eligible_pixels == 16);
    const weak: [45]f32 = [0.3] ** 45;
    assert(auto_white_balance.propose(weak[0..], 15, 1,
        4, no_cancel, 0
    ).status == 4);
}

test "gray-world rejects a strongly colored eligible scene" {
    var input: [48]f32 = [0.0] ** 48;
    var pixel: usize = 0;
    while pixel < 16 {
        input[pixel * 3] = 0.025;
        input[pixel * 3 + 1] = 0.975;
        input[pixel * 3 + 2] = 0.975;
        pixel = pixel + 1;
    }
    const proposal = auto_white_balance.propose(input[0..], 4, 4,
        31, no_cancel, 0
    );
    assert(proposal.status == 5 and proposal.eligible_pixels == 0);
}

test "auto white balance validates identity shape input and cancellation" {
    const input: [3]f32 = [0.3, 0.3, 0.3];
    assert(auto_white_balance.propose(input[0..], 1, 1,
        0, no_cancel, 0
    ).status == 1);
    assert(auto_white_balance.propose(input[0..], 2, 1,
        1, no_cancel, 0
    ).status == 2);
    const invalid: [3]f32 = [9.0, 0.3, 0.3];
    assert(auto_white_balance.propose(invalid[0..], 1, 1,
        1, no_cancel, 0
    ).status == 3);
    assert(auto_white_balance.propose(input[0..], 1, 1,
        1, cancel, 0
    ).status == 7);
}
