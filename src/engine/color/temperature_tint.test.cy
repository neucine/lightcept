import .engine.color.temperature_tint;

fn close(actual: f64, expected: f64, tolerance: f64): bool {
    const difference = actual - expected;
    return difference < tolerance and difference > -tolerance;
}

test "temperature/tint round-trips through xy coordinates" {
    var kelvin: f64 = 2000.0;
    while kelvin <= 50000.0 {
        var tint: f64 = -100.0;
        while tint <= 100.0 {
            const xy = temperature_tint.to_xy(kelvin, tint);
            const recovered = temperature_tint.from_xy(xy);
            assert(close(recovered[0], kelvin, kelvin * 0.001));
            assert(close(recovered[1], tint, 0.25));
            tint = tint + 50.0;
        }
        kelvin = kelvin * 2.0;
    }
}

test "temperature/tint maps a neutral daylight point near D65" {
    const xy = temperature_tint.to_xy(6500.0, 0.0);
    assert(close(xy[0], 0.3135, 0.002));
    assert(close(xy[1], 0.3237, 0.002));
}

test "temperature/tint keeps the locus continuous at the polynomial bound" {
    const below = temperature_tint.to_xy(1667.0, 0.0);
    const above = temperature_tint.to_xy(1667.0000001, 0.0);
    assert(close(below[0], above[0], 0.000001));
    assert(close(below[1], above[1], 0.000001));
}
