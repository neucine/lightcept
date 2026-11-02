import .engine.analysis.color_cast;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn full_region(): color_cast.NeutralRegion {
    return {
        left: 0,
        top: 0,
        width: 2,
        height: 2
    };
}

test "neutral patch reports unit channel ratios" {
    const pixels: [12]f32 = [0.25, 0.25, 0.25, 0.5, 0.5, 0.5,
        0.25, 0.25, 0.25, 0.5, 0.5, 0.5
    ];
    const report = color_cast.measure(pixels[0..], 2, 2,
        full_region(), 17, no_cancel, 0
    );
    assert(report.status == 0 and report.version == 1);
    assert(report.pixels == 4 and report.matrix_hash == 17);
    assert(report.red_ratio > 0.9999 and report.red_ratio < 1.0001);
    assert(report.green_ratio > 0.9999 and report.green_ratio < 1.0001);
    assert(report.blue_ratio > 0.9999 and report.blue_ratio < 1.0001);
}

test "red-biased patch gives a measured red ratio" {
    const pixels: [12]f32 = [0.5, 0.25, 0.25, 0.5, 0.25, 0.25,
        0.5, 0.25, 0.25, 0.5, 0.25, 0.25
    ];
    const report = color_cast.measure(pixels[0..], 2, 2,
        full_region(), 18, no_cancel, 0
    );
    assert(report.status == 0);
    assert(report.red_ratio > 1.5 and report.green_ratio < 1.0);
    assert(report.mean_red == 0.5 and report.mean_blue == 0.25);
}

test "color cast reads only the declared neutral patch" {
    const pixels: [12]f32 = [9.0, 9.0, 9.0, 0.4, 0.4, 0.4,
        9.0, 9.0, 9.0, 9.0, 9.0, 9.0
    ];
    const region: color_cast.NeutralRegion = {
        left: 1,
        top: 0,
        width: 1,
        height: 1
    };
    const report = color_cast.measure(pixels[0..], 2, 2,
        region, 19, no_cancel, 0
    );
    assert(report.status == 0 and report.pixels == 1);
    assert(report.red_ratio > 0.9999 and report.red_ratio < 1.0001);
    const invalid_region: color_cast.NeutralRegion = {
        left: 0,
        top: 0,
        width: 1,
        height: 1
    };
    assert(color_cast.measure(pixels[0..], 2, 2,
        invalid_region, 19, no_cancel, 0
    ).status == 3);
}

test "color cast rejects missing provenance shape dark reference and cancellation" {
    const pixels: [12]f32 = [0.0] ** 12;
    const dark = color_cast.measure(pixels[0..], 2, 2,
        full_region(), 1, no_cancel, 0
    );
    assert(dark.status == 4 and dark.pixels == 0);
    assert(color_cast.measure(pixels[0..], 3, 2,
        full_region(), 1, no_cancel, 0
    ).status == 1);
    assert(color_cast.measure(pixels[0..], 2, 2,
        full_region(), 0, no_cancel, 0
    ).status == 2);
    assert(color_cast.measure(pixels[0..], 2, 2,
        full_region(), 1, cancel, 0
    ).status == 7);
}
