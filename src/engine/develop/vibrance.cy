// Diagnostic linear-working vibrance v1. Signed Rec.2020/D65 RGB is measured
// against BT.2020 luminance. Low-chroma colors receive more of the requested
// chroma change; luminance and hue direction are retained. This is not a
// perceptual-space or skin-tone-aware vibrance operator.
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

fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}
fn maximum3(a: f64, b: f64, c: f64): f64 {
    var result = a;
    if b > result {
        result = b;
    }
    if c > result {
        result = c;
    }
    return result;
}

pub fn apply(red: f64, green: f64, blue: f64, strength: f64): LinearRgb {
    if strength == 0.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const r = red;
    const g = green;
    const b = blue;
    const y = 0.2627 * r + 0.6780 * g + 0.0593 * b;
    const chroma = maximum3(absolute(r - y), absolute(g - y), absolute(b - y));
    const factor = 1.0 + strength / (1.0 + 4.0 * chroma);
    return {
        red: (y + (r - y) * factor),
        green: (y + (g - y) * factor),
        blue: (y + (b - y) * factor)
    };
}
