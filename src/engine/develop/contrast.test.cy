import .engine.develop.contrast;

test "contrast preserves neutral identity, pivot, chroma and headroom" {
    const neutral = contrast.apply(-0.2, 0.18, 1.4, 1.0);
    assert(neutral.red == -0.2 and neutral.green == 0.18 and neutral.blue == 1.4);
    const pivot = contrast.apply(0.18, 0.18, 0.18, 2.0);
    assert(pivot.red == 0.18 and pivot.green == 0.18 and pivot.blue == 0.18);
    const dark = contrast.apply(0.0, 0.0, 0.0, 2.0);
    const bright = contrast.apply(1.5, 1.5, 1.5, 2.0);
    assert(dark.red < 0.0 and bright.red > 1.5);
    const color = contrast.apply(0.8, 0.2, -0.1, 1.5);
    assert(color.red - color.green > 0.599999 and color.red - color.green < 0.600001);
    assert(contrast.valid_slope(0.5) and contrast.valid_slope(2.0));
    assert(not contrast.valid_slope(0.49) and not contrast.valid_slope(2.01));
    assert(contrast.slope_from_percent(-100.0) == 0.5);
    assert(contrast.slope_from_percent(0.0) == 1.0);
    assert(contrast.slope_from_percent(100.0) == 2.0);
}
