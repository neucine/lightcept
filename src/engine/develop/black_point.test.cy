import .engine.develop.black_point;

test "black offset has exact neutral identity and known scene-linear vectors" {
    const neutral = black_point.apply(-0.25, 0.18, 1.5, 0.0);
    assert(neutral.red == -0.25 and neutral.green == 0.18 and neutral.blue == 1.5);
    const lowered = black_point.apply(0.0, 0.18, 1.5, 0.125);
    assert(lowered.red == -0.125);
    assert(lowered.green > 0.054999 and lowered.green < 0.055001);
    assert(lowered.blue == 1.375);
    const lifted = black_point.apply(-0.25, 0.0, 1.5, -0.125);
    assert(lifted.red == -0.125 and lifted.green == 0.125 and lifted.blue == 1.625);
}

test "black offset retains signed headroom and absolute channel differences" {
    const source = black_point.apply(0.8, 0.2, -0.1, 0.0625);
    assert(source.red - source.green > 0.599999 and source.red - source.green < 0.600001);
    assert(source.blue < 0.0);
    const headroom = black_point.apply(2.0, 1.5, 1.25, -0.125);
    assert(headroom.red > 2.0 and headroom.green > 1.5);
    assert(black_point.valid_offset(-0.125) and black_point.valid_offset(0.125));
    assert(not black_point.valid_offset(-0.126) and not black_point.valid_offset(0.126));
}
