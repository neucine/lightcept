import .engine.develop.linear_chroma;

test "linear chroma preserves Rec.2020 luminance and signed headroom" {
    const red = -0.25 as c_double;
    const green = 0.4 as c_double;
    const blue = 1.5 as c_double;
    const baseline = 0.2627 * (red as f64) + 0.6780 * (green as f64) + 0.0593 * (blue as f64);
    const neutral = linear_chroma.apply(red, green, blue, 1.0);
    assert(neutral.red == red and neutral.green == green and neutral.blue == blue);
    const zero = linear_chroma.apply(red, green, blue, 0.0);
    assert(zero.red == zero.green and zero.green == zero.blue);
    const vivid = linear_chroma.apply(red, green, blue, 1.5);
    const y = 0.2627 * (vivid.red as f64) + 0.6780 * (vivid.green as f64) + 0.0593 * (vivid.blue as f64);
    const error = y - baseline;
    assert(error * error < 0.000000000001);
    assert((vivid.red as f64) < 0.0 and (vivid.blue as f64) > 1.0);
}
