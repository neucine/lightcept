import .engine.analysis.histogram;

test "linear luminance histogram has explicit signed and highlight bins" {
    assert(histogram.bin_for_luminance(-0.01) == 0);
    assert(histogram.bin_for_luminance(0.0) == 1);
    assert(histogram.bin_for_luminance(0.5) == 129);
    assert(histogram.bin_for_luminance(255.0 / 256.0) == 256);
    assert(histogram.bin_for_luminance(1.0) == 257);
    assert(histogram.bin_for_luminance(2.0) == 257);
}

test "histogram merge count checks the full-frame bound" {
    assert(histogram.count_fits(10, 3, 13));
    assert(not histogram.count_fits(10, 4, 13));
    assert(not histogram.count_fits(14, 0, 13));
}
