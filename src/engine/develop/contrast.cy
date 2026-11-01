// Diagnostic scene-linear contrast v1. The input is signed Rec.2020/D65 RGB.
// A positive slope expands luminance about 18% grey; negative samples and
// values above reference white are retained. Absolute chroma is unchanged.
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

pub fn slope_from_percent_native(percent: f64): f64 {
    if percent < 0.0 {
        return 1.0 + percent * 0.005;
    }
    return 1.0 + percent * 0.01;
}

pub fn valid_slope(slope: c_double): bool {
    return slope >= slope_min() and slope <= slope_max();
}

pub fn slope_min(): c_double {
    return 0.5;
}
pub fn slope_max(): c_double {
    return 2.0;
}

// Diagnostic product-percent translation v1. A negative percentage contracts
// luminance toward 18% grey; a positive percentage expands it. The asymmetric
// spans use the whole admissible slope range with zero as exact identity.
pub fn slope_from_percent(percent: c_double): c_double {
    return slope_from_percent_native(percent as f64) as c_double;
}

// Status: 0 success, 3 shape, 4 invalid percentage.
export c("lc_cyna_img_v1_contrast_slope_from_percent") fn contrast_slope_from_percent(percent: c_double, output: *c_double, output_len: c_size_t): c_int {
    if output_len as usize != 1 {
        return 3;
    }
    if not (percent >= -100.0 and percent <= 100.0) {
        return 4;
    }
    unchecked {
        *(output as! *c_double) = slope_from_percent(percent);
    }
    return 0;
}

pub fn apply_native(red: f64, green: f64, blue: f64, slope: f64): NativeRgb {
    if slope == 1.0 {
        return {
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const new_y = 0.18 + slope * (y - 0.18);
    const offset = new_y - y;
    return {
        red: red + offset,
        green: green + offset,
        blue: blue + offset
    };
}

pub fn apply(red: c_double, green: c_double, blue: c_double, slope: c_double): LinearRgb {
    const result = apply_native(red as f64, green as f64, blue as f64, slope as f64);
    return {
        red: result.red as c_double,
        green: result.green as c_double,
        blue: result.blue as c_double
    };
}
