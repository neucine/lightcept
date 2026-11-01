import .engine.develop.vibrance;

test "linear vibrance has exact neutral identity and retains luminance" {
    const original = vibrance.apply(-0.2, 0.18, 1.4, 0.0);
    assert(original.red == -0.2 and original.green == 0.18 and original.blue == 1.4);
    const grey = vibrance.apply(0.18, 0.18, 0.18, 1.0);
    assert(grey.red == 0.18 and grey.green == 0.18 and grey.blue == 0.18);
    const changed = vibrance.apply(0.8, 0.2, 0.2, 0.75);
    const before_y = 0.2627 * 0.8 + 0.6780 * 0.2 + 0.0593 * 0.2;
    const after_y = 0.2627 * (changed.red as f64) + 0.6780 * (changed.green as f64) + 0.0593 * (changed.blue as f64);
    assert(after_y > before_y - 0.000001 and after_y < before_y + 0.000001);
    assert(changed.red > 0.8 and changed.green < 0.2);
}

test "linear vibrance prioritizes low chroma and preserves hue direction" {
    const low = vibrance.apply(0.3, 0.2, 0.2, 1.0);
    const high = vibrance.apply(0.8, 0.2, 0.2, 1.0);
    assert((low.red - low.green) / 0.1 > (high.red - high.green) / 0.6);
    assert(low.red > low.green and high.red > high.green);
    const less = vibrance.apply(0.8, 0.2, 0.2, -1.0);
    assert(less.red > less.green and less.red - less.green < 0.6);
    const signed = vibrance.apply(-0.2, 0.2, 1.5, 0.5);
    assert(signed.red < 0.0 and signed.blue > 1.5);
    assert(vibrance.valid_strength(-1.0) and vibrance.valid_strength(1.0));
    assert(not vibrance.valid_strength(-1.01) and not vibrance.valid_strength(1.01));
}
