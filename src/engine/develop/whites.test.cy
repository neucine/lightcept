import .engine.develop.whites;

test "whites pivot and neutral are exact and analytical greys retain headroom" {
    const neutral = whites.apply(-0.2, 0.7, 2.0, 0.0);
    assert(neutral.red == -0.2 and neutral.green == 0.7 and neutral.blue == 2.0);
    const pivot = whites.apply(0.5, 0.5, 0.5, 1.0);
    assert(pivot.red == 0.5 and pivot.green == 0.5 and pivot.blue == 0.5);
    const shadow = whites.apply(-0.2, -0.2, -0.2, 1.0);
    assert(shadow.red == -0.2);
    const white = whites.apply(1.0, 1.0, 1.0, 1.0);
    assert(white.red == 1.5 and white.green == 1.5 and white.blue == 1.5);
    const lowered = whites.apply(1.0, 1.0, 1.0, -0.5);
    assert(lowered.red == 0.75);
    const headroom = whites.apply(2.0, 2.0, 2.0, 1.0);
    assert(headroom.red == 3.5);
}

test "whites preserves channel differences and validates strength" {
    const color = whites.apply(1.0, 0.7, 0.4, 0.5);
    assert(color.red - color.green > 0.299999 and color.red - color.green < 0.300001);
    assert(whites.valid_strength(-0.5) and whites.valid_strength(1.0));
    assert(not whites.valid_strength(-0.51) and not whites.valid_strength(1.01));
}
