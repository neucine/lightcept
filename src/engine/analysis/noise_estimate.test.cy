import .engine.analysis.noise_estimate;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "same-CFA second differences reject a smooth photographic ramp" {
    var mosaic: [64]f32 = [0.0] ** 64;
    var row: usize = 0;
    while row < 8 {
        var column: usize = 0;
        while column < 8 {
            mosaic[row * 8 + column] = (0.25 + (column as f64) * 0.015625) as f32;
            column = column + 1;
        }
        row = row + 1;
    }
    const cfa: [4]u32 = [0, 1, 1, 2];
    const result = noise_estimate.measure(mosaic[0..], 8, 8, cfa, no_cancel, 0);
    assert(result.status == 0 and result.red_count == 8
        and result.green_count == 16 and result.blue_count == 8
    );
    assert(result.red_variance < 0.000000000001
        and result.green_variance < 0.000000000001
        and result.blue_variance < 0.000000000001
    );
}

test "alternating same-color samples produce analytical residual energy" {
    var mosaic: [64]f32 = [0.0] ** 64;
    var row: usize = 0;
    while row < 8 {
        var column: usize = 0;
        while column < 8 {
            if (column / 2) % 2 == 0 {
                mosaic[row * 8 + column] = 0.1;
            } else {
                mosaic[row * 8 + column] = 0.3;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    const result = noise_estimate.measure(mosaic[0..], 8, 8,
        [0, 1, 1, 2], no_cancel, 0
    );
    assert(result.status == 0);
    assert(result.red_variance > 0.02666 and result.red_variance < 0.02667);
    assert(result.green_variance > 0.02666 and result.green_variance < 0.02667);
    assert(result.blue_sigma > 0.1632 and result.blue_sigma < 0.1634);
}

test "noise estimate validates CFA, sample domain, and cancellation" {
    var mosaic: [64]f32 = [0.2] ** 64;
    assert(noise_estimate.measure(mosaic[0..63], 8, 8,
        [0, 1, 1, 2], no_cancel, 0
    ).status == 1);
    assert(noise_estimate.measure(mosaic[0..], 8, 8,
        [0, 0, 1, 2], no_cancel, 0
    ).status == 2);
    assert(noise_estimate.measure(mosaic[0..], 8, 8,
        [0, 2, 1, 1], no_cancel, 0
    ).status == 2);
    mosaic[10] = 9.0;
    const bad = noise_estimate.measure(mosaic[0..], 8, 8,
        [0, 1, 1, 2], no_cancel, 0
    );
    assert(bad.status == 3 and bad.red_count == 0);
    mosaic[10] = 0.2;
    const stopped = noise_estimate.measure(mosaic[0..], 8, 8,
        [0, 1, 1, 2], cancel, 0
    );
    assert(stopped.status == 7 and stopped.red_count == 0);
}
