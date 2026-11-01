// Diagnostic pointwise scene-linear highlight band v1. Input/output: signed
// Rec.2020/D65 RGB. The adjustment is confined to luminance (0.18, 1),
// retains both endpoints and headroom above reference white, and preserves
// absolute channel differences. It is not highlight reconstruction.
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
    if y <= 0.18 or y >= 1.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const span = 1.0 - 0.18;
    const position = (y - 0.18) / span;
    const offset = strength * span * position * (1.0 - position);
    return {
        red: (red + offset),
        green: (green + offset),
        blue: (blue + offset)
    };
}
