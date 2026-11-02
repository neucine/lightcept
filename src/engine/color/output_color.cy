// D65 Rec.2020 to encoded sRGB. Clipping is output-only.
import std.math;

pub fn exposure_gain_native(ev: f64): f64 {
    return math.pow_f64(2.0, ev);
}

pub fn exposure_gain(ev: f64): f64 {
    return exposure_gain_native(ev);
}

// D65 Rec.2020 to D65 linear sRGB, followed by clipping and the IEC sRGB curve.
// channel is 0=red, 1=green, 2=blue; callers validate this selector.
pub fn encode_channel(red: f64, green: f64, blue: f64, channel: i32): f64 {
    // Keep decimal matrix coefficients in f64 through the output transform.
    const r = red;
    const g = green;
    const b = blue;
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
        return (12.92 * linear) as f64;
    }
    return (1.055 * (math.pow_f64(linear as f64, 0.4166666666666667) as f64) - 0.055) as f64;
}

// Diagnostic split of the accepted fused output operation. These functions
// name the three responsibilities without changing the existing output plan.
pub fn rec2020_to_linear_srgb_channel(red: f64, green: f64, blue: f64, channel: i32): f64 {
    const r: f64 = red as f64;
    const g: f64 = green as f64;
    const b: f64 = blue as f64;
    if channel == 0 {
        return (1.660491 * r - 0.587641 * g - 0.072850 * b) as f64;
    }
    if channel == 1 {
        return (-0.124550 * r + 1.132900 * g - 0.008349 * b) as f64;
    }
    return (-0.018151 * r - 0.100579 * g + 1.118730 * b) as f64;
}

pub fn clip_linear_srgb(value: f64): f64 {
    if value <= 0.0 {
        return 0.0;
    }
    if value >= 1.0 {
        return 1.0;
    }
    return value;
}

pub fn srgb_transfer(linear: f64): f64 {
    if linear <= 0.0031308 {
        return (12.92 * (linear as f64)) as f64;
    }
    return (1.055 * (math.pow_f64(linear, 0.4166666666666667) as f64) - 0.055) as f64;
}

pub fn encode_channel_split(red: f64, green: f64, blue: f64, channel: i32): f64 {
    const linear = rec2020_to_linear_srgb_channel(red, green, blue, channel);
    const clipped = clip_linear_srgb(linear);
    if clipped == 0.0 or clipped == 1.0 {
        return clipped;
    }
    return srgb_transfer(clipped);
}
