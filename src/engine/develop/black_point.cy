// Diagnostic scene-linear black offset v1, distinct from sensor black-level
// calibration. Input/output: signed Rec.2020/D65 linear RGB. The offset is in
// linear reference-white units; positive values lower all channels equally.
// No clamp occurs here. The later output branch owns gamut clipping.
pub struct LinearRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn minimum(): f64 {
    return -0.125;
}
pub fn maximum(): f64 {
    return 0.125;
}

pub fn valid_offset(offset: f64): bool {
    return offset >= minimum() and offset <= maximum();
}

pub fn apply(red: f64, green: f64, blue: f64, offset: f64): LinearRgb {
    if offset == 0.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    return {
        red: (red - offset),
        green: (green - offset),
        blue: (blue - offset)
    };
}
