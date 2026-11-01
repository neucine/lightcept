// Scene-linear Rec.2020 luminance coefficients (BT.2020/D65). This operation
// retains signed values and highlight headroom; output encoding clips later.
pub struct LinearRgb {
    pub red: c_double;
    pub green: c_double;
    pub blue: c_double;
}

pub struct NativeRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn apply_native(red: f64, green: f64, blue: f64, factor: f64): NativeRgb {
    if factor == 1.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    return {
        red: y + factor * (red - y),
        green: y + factor * (green - y),
        blue: y + factor * (blue - y)
    };
}

pub fn apply(red: c_double, green: c_double, blue: c_double, factor: c_double): LinearRgb {
    const result = apply_native(red as f64, green as f64, blue as f64, factor as f64);
    return {
        red: result.red as c_double,
        green: result.green as c_double,
        blue: result.blue as c_double,
    };
}
