// D65 Rec.2020 to encoded sRGB. Clipping is output-only.
extern c("pow") fn pow(base: c_double, exponent: c_double): c_double;

pub fn exposure_gain_native(ev: f64): f64 {
    return pow(2.0, ev as c_double) as f64;
}

pub fn exposure_gain(ev: c_double): c_double {
    return exposure_gain_native(ev as f64) as c_double;
}

// D65 Rec.2020 to D65 linear sRGB, followed by clipping and the IEC sRGB curve.
// channel is 0=red, 1=green, 2=blue; callers validate this selector.
pub fn encode_channel(red: c_double, green: c_double, blue: c_double, channel: c_int): c_double {
    // Cyna keeps C ABI scalar aliases distinct. Work in f64 so decimal coefficients
    // retain their intended precision without checked f64-to-c_float casts.
    const r: f64 = red as f64;
    const g: f64 = green as f64;
    const b: f64 = blue as f64;
    var linear: f64 = 0.0;
    if channel == 0 {
        linear = 1.660491 * r - 0.587641 * g - 0.072850 * b;
    } else if channel == 1 {
        linear = -0.124550 * r + 1.132900 * g - 0.008349 * b;
    } else {
        linear = -0.018151 * r - 0.100579 * g + 1.118730 * b;
    }
    if linear <= 0.0 {
        return 0.0;
    }
    if linear >= 1.0 {
        return 1.0;
    }
    if linear <= 0.0031308 {
        return (12.92 * linear) as c_double;
    }
    return (1.055 * (pow(linear as c_double, 0.4166666666666667) as f64) - 0.055) as c_double;
}

// Diagnostic split of the accepted fused output operation. These functions
// name the three responsibilities without changing the existing ABI or plan.
pub fn rec2020_to_linear_srgb_channel(red: c_double, green: c_double, blue: c_double, channel: c_int): c_double {
    const r: f64 = red as f64;
    const g: f64 = green as f64;
    const b: f64 = blue as f64;
    if channel == 0 {
        return (1.660491 * r - 0.587641 * g - 0.072850 * b) as c_double;
    }
    if channel == 1 {
        return (-0.124550 * r + 1.132900 * g - 0.008349 * b) as c_double;
    }
    return (-0.018151 * r - 0.100579 * g + 1.118730 * b) as c_double;
}

pub fn clip_linear_srgb(value: c_double): c_double {
    if value <= 0.0 {
        return 0.0;
    }
    if value >= 1.0 {
        return 1.0;
    }
    return value;
}

pub fn srgb_transfer(linear: c_double): c_double {
    if linear <= 0.0031308 {
        return (12.92 * (linear as f64)) as c_double;
    }
    return (1.055 * (pow(linear, 0.4166666666666667) as f64) - 0.055) as c_double;
}

pub fn encode_channel_split(red: c_double, green: c_double, blue: c_double, channel: c_int): c_double {
    const linear = rec2020_to_linear_srgb_channel(red, green, blue, channel);
    const clipped = clip_linear_srgb(linear);
    if clipped == 0.0 or clipped == 1.0 {
        return clipped;
    }
    return srgb_transfer(clipped);
}
