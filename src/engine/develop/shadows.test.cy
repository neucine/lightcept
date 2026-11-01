import .engine.develop.shadows;

test "shadow band has exact neutral and endpoint identities" {
    const neutral = shadows.apply(-0.2, 0.09, 1.4, 0.0);
    assert(neutral.red == -0.2 and neutral.green == 0.09 and neutral.blue == 1.4);
    const black = shadows.apply(0.0, 0.0, 0.0, 1.0);
    assert(black.red == 0.0 and black.green == 0.0 and black.blue == 0.0);
    const middle = shadows.apply(0.18, 0.18, 0.18, 1.0);
    assert(middle.red == 0.18 and middle.green == 0.18 and middle.blue == 0.18);
    const signed = shadows.apply(-0.1, -0.1, -0.1, 1.0);
    assert(signed.red == -0.1);
    const headroom = shadows.apply(2.0, 2.0, 2.0, 1.0);
    assert(headroom.red == 2.0);
}

test "shadow band is monotone on analytical greys and preserves chroma" {
    const low = shadows.apply(0.045, 0.045, 0.045, 1.0);
    const middle = shadows.apply(0.09, 0.09, 0.09, 1.0);
    assert(middle.red > 0.134999 and middle.red < 0.135001);
    const high = shadows.apply(0.135, 0.135, 0.135, 1.0);
    assert(low.red > 0.045 and low.red < middle.red and middle.red < high.red and high.red < 0.18);
    const darkened = shadows.apply(0.09, 0.09, 0.09, -1.0);
    assert(darkened.red > 0.0 and darkened.red < 0.09);
    const color = shadows.apply(0.16, 0.08, 0.02, 0.5);
    assert(color.red - color.green > 0.079999 and color.red - color.green < 0.080001);
    assert(shadows.valid_strength(-1.0) and shadows.valid_strength(1.0));
    assert(not shadows.valid_strength(-1.01) and not shadows.valid_strength(1.01));
}
