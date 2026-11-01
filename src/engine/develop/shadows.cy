// Diagnostic pointwise scene-linear shadow band v1. Input/output: signed
// Rec.2020/D65 RGB. The adjustment is confined to luminance (0, 0.18),
// preserves both endpoints and absolute channel differences, and does not
// perform a spatial estimate or clip the result.
pub struct LinearRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn minimum(): f64 {
    return -1.0;
}
pub fn maximum(): f64 {
    return 1.0;
}
pub fn valid_strength(strength: f64): bool {
    return strength >= minimum() and strength <= maximum();
}

pub fn apply(red: f64, green: f64, blue: f64, strength: f64): LinearRgb {
    if strength == 0.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    if y <= 0.0 or y >= 0.18 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const offset = strength * y * (1.0 - y / 0.18);
    return {
        red: (red + offset),
        green: (green + offset),
        blue: (blue + offset)
    };
}
