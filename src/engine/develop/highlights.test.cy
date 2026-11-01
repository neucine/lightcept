import .engine.develop.highlights;

test "highlight band has exact neutral and endpoint identities" {
    const neutral = highlights.apply(-0.2, 0.6, 1.4, 0.0);
    assert(neutral.red == -0.2 and neutral.green == 0.6 and neutral.blue == 1.4);
    const pivot = highlights.apply(0.18, 0.18, 0.18, -1.0);
    assert(pivot.red == 0.18 and pivot.green == 0.18 and pivot.blue == 0.18);
    const white = highlights.apply(1.0, 1.0, 1.0, -1.0);
    assert(white.red == 1.0);
    const headroom = highlights.apply(2.0, 2.0, 2.0, -1.0);
    assert(headroom.red == 2.0);
    const signed = highlights.apply(-0.25, -0.25, -0.25, 1.0);
    assert(signed.red == -0.25);
}

test "highlight band is monotone and preserves chroma" {
    const low = highlights.apply(0.385, 0.385, 0.385, -1.0);
    const middle = highlights.apply(0.59, 0.59, 0.59, -1.0);
    assert(middle.red > 0.384999 and middle.red < 0.385001);
    const high = highlights.apply(0.795, 0.795, 0.795, -1.0);
    assert(low.red > 0.18 and low.red < middle.red and middle.red < high.red and high.red < 1.0);
    const lifted = highlights.apply(0.59, 0.59, 0.59, 1.0);
    assert(lifted.red > 0.59 and lifted.red < 1.0);
    const color = highlights.apply(0.8, 0.5, 0.2, -0.5);
    assert(color.red - color.green > 0.299999 and color.red - color.green < 0.300001);
    assert(highlights.valid_strength(-1.0) and highlights.valid_strength(1.0));
    assert(not highlights.valid_strength(-1.01) and not highlights.valid_strength(1.01));
}
