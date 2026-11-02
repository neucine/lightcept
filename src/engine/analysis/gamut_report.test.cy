import .engine.analysis.gamut_report;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "sRGB gamut report counts destination channel excursions" {
    const input: [12]f32 = [0.25, 0.25, 0.25,
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0
    ];
    const report = gamut_report.measure(input[0..], 2, 2,
        gamut_report.srgb_destination(12), no_cancel, 0
    );
    assert(report.status == 0 and report.version == 1);
    assert(report.profile_hash == 12 and report.pixels == 4);
    assert(report.outside_pixels == 3);
    assert(report.above_one[0] == 1 and report.above_one[1] == 1);
    assert(report.above_one[2] == 1);
    assert(report.below_zero[0] == 2 and report.below_zero[1] == 2);
    assert(report.below_zero[2] == 2);
    assert(report.maximum_excursion > 0.6);
}

test "declared identity gamut preserves in-range working pixels" {
    const input: [6]f32 = [0.0, 0.5, 1.0, 0.2, 0.4, 0.6];
    const identity: gamut_report.DestinationMatrix = {
        version: 1,
        profile_hash: 23,
        rows: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
    };
    const report = gamut_report.measure(input[0..], 2, 1, identity,
        no_cancel, 0
    );
    assert(report.status == 0 and report.outside_pixels == 0);
    assert(report.maximum_excursion == 0.0);
}

test "identity gamut reports exact linear channel excursions" {
    const input: [3]f32 = [-0.25, 0.5, 1.5];
    const identity: gamut_report.DestinationMatrix = {
        version: 1,
        profile_hash: 24,
        rows: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
    };
    const report = gamut_report.measure(input[0..], 1, 1, identity,
        no_cancel, 0
    );
    assert(report.status == 0 and report.outside_pixels == 1);
    assert(report.below_zero[0] == 1 and report.above_one[2] == 1);
    assert(report.maximum_excursion == 0.5);
}

test "gamut report rejects invalid asset input and cancellation" {
    const input: [3]f32 = [0.25, 0.25, 0.25];
    var asset = gamut_report.srgb_destination(1);
    asset.profile_hash = 0;
    assert(gamut_report.measure(input[0..], 1, 1, asset,
        no_cancel, 0
    ).status == 1);
    asset.profile_hash = 1;
    assert(gamut_report.measure(input[0..], 2, 1, asset,
        no_cancel, 0
    ).status == 2);
    const invalid: [3]f32 = [9.0, 0.25, 0.25];
    assert(gamut_report.measure(invalid[0..], 1, 1, asset,
        no_cancel, 0
    ).status == 3);
    assert(gamut_report.measure(input[0..], 1, 1, asset,
        cancel, 0
    ).status == 7);
}
