import .engine.color.relative_white;

test "relative white gains are bounded and neutral is identity" {
    const neutral = relative_white.gains(0, 0);
    assert(neutral.red == 1.0 and neutral.green == 1.0 and neutral.blue == 1.0);
    const warm = relative_white.gains(100, 0);
    assert(warm.red == 1.5 and warm.green == 1.0 and warm.blue == 0.5);
    const magenta = relative_white.gains(0, 100);
    assert(magenta.red == 1.25 and magenta.green == 0.5 and magenta.blue == 1.25);
    assert(relative_white.valid(-100, 100));
    assert(not relative_white.valid(101, 0) and not relative_white.valid(0, -101));
}
