import .engine.analysis.histogram;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "linear luminance histogram has explicit signed and highlight bins" {
    assert(histogram.bin_for_luminance(-0.01) == 0);
    assert(histogram.bin_for_luminance(0.0) == 1);
    assert(histogram.bin_for_luminance(0.5) == 129);
    assert(histogram.bin_for_luminance(255.0 / 256.0) == 256);
    assert(histogram.bin_for_luminance(1.0) == 257);
    assert(histogram.bin_for_luminance(2.0) == 257);
}

test "headless histogram counts a signed to highlight scene strip" {
    const input: [12]f32 = [-0.1, -0.1, -0.1,
        0.0, 0.0, 0.0, 0.5, 0.5, 0.5,
        1.5, 1.5, 1.5
    ];
    var bins: [258]u32 = [99] ** 258;
    const asset: histogram.HistogramAsset = {
        version: 1
    };
    assert(histogram.build(input[0..], 4, 1, asset,
        bins[0..], no_cancel, 0
    ) == 0);
    assert(bins[0] == 1 and bins[1] == 1
        and bins[129] == 1 and bins[257] == 1
    );
    assert(bins[128] == 0 and bins[256] == 0);
}

test "headless histogram rejects invalid source shape and cancellation" {
    const input: [3]f32 = [0.5, 0.5, 0.5];
    var bins: [258]u32 = [99] ** 258;
    const asset: histogram.HistogramAsset = {
        version: 1
    };
    assert(histogram.build(input[0..], 0, 1, asset,
        bins[0..], no_cancel, 0
    ) == 2);
    var short: [2]u32 = [99, 99];
    assert(histogram.build(input[0..], 1, 1, asset,
        short[0..], no_cancel, 0
    ) == 4);
    const invalid: [3]f32 = [9.0, 0.5, 0.5];
    assert(histogram.build(invalid[0..], 1, 1, asset,
        bins[0..], no_cancel, 0
    ) == 3);
    assert(histogram.build(input[0..], 1, 1, asset,
        bins[0..], cancel, 0
    ) == 7);
    const wrong: histogram.HistogramAsset = {
        version: 2
    };
    assert(histogram.build(input[0..], 1, 1, wrong,
        bins[0..], no_cancel, 0
    ) == 1);
    assert(bins[0] == 99);
}

test "histogram merge count checks the full-frame bound" {
    assert(histogram.count_fits(10, 3, 13));
    assert(not histogram.count_fits(10, 4, 13));
    assert(not histogram.count_fits(14, 0, 13));
}
