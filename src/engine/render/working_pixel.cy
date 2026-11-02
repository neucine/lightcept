import .engine.develop.exposure;
import .engine.develop.linear_chroma;
import .engine.develop.contrast;
import .engine.color.white_balance;
import .engine.color.output_color;

// Working RGB adjustment followed by sRGB output encoding.

pub struct EncodedRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub struct WorkingSrgbPlan {
    pub exposure_ev: f64;
    pub red_gain: f64;
    pub green_gain: f64;
    pub blue_gain: f64;
    pub linear_chroma: f64;
}

pub fn encode_working_srgb_plan_pixel(red: f32, green: f32, blue: f32, plan: WorkingSrgbPlan): EncodedRgb {
    return encode_working_pixel_with_chroma(red as f64, green as f64, blue as f64, plan);
}

pub fn encode_working_pixel_with_contrast(red: f64, green: f64, blue: f64, plan: WorkingSrgbPlan, slope: f64): EncodedRgb {
    if slope == 1.0 {
        return encode_working_pixel_with_chroma(red, green, blue, plan);
    }
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain as f64), plan.red_gain as f64) as f64;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain as f64), plan.green_gain as f64) as f64;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain as f64), plan.blue_gain as f64) as f64;
    const toned = contrast.apply(r, g, b, slope);
    const adjusted = linear_chroma.apply(toned.red, toned.green, toned.blue, plan.linear_chroma);
    return {
        red: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 0),
        green: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 1),
        blue: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 2),
    };
}

pub fn encode_pixel(red: f32, green: f32, blue: f32, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): EncodedRgb {
    return encode_working_pixel(red as f64, green as f64, blue as f64, exposure_ev, red_gain, green_gain, blue_gain);
}

pub fn encode_working_pixel(red: f64, green: f64, blue: f64, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): EncodedRgb {
    const ev: f64 = exposure_ev as f64;
    const exposure_gain: f64 = output_color.exposure_gain(ev as f64) as f64;
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain), red_gain as f64) as f64;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain), green_gain as f64) as f64;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain), blue_gain as f64) as f64;
    return {
        red: output_color.encode_channel(r, g, b, 0),
        green: output_color.encode_channel(r, g, b, 1),
        blue: output_color.encode_channel(r, g, b, 2),
    };
}

pub fn encode_working_pixel_with_chroma(red: f64, green: f64, blue: f64, plan: WorkingSrgbPlan): EncodedRgb {
    if plan.linear_chroma == 1.0 {
        return encode_working_pixel(red, green, blue, plan.exposure_ev, plan.red_gain, plan.green_gain, plan.blue_gain);
    }
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain as f64), plan.red_gain as f64) as f64;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain as f64), plan.green_gain as f64) as f64;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain as f64), plan.blue_gain as f64) as f64;
    const adjusted = linear_chroma.apply(r, g, b, plan.linear_chroma);
    return {
        red: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 0),
        green: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 1),
        blue: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 2),
    };
}

pub fn encode_working_pixel_split(red: f64, green: f64, blue: f64, plan: WorkingSrgbPlan): EncodedRgb {
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain as f64), plan.red_gain as f64) as f64;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain as f64), plan.green_gain as f64) as f64;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain as f64), plan.blue_gain as f64) as f64;
    if plan.linear_chroma == 1.0 {
        return {
            red: output_color.encode_channel_split(r, g, b, 0),
            green: output_color.encode_channel_split(r, g, b, 1),
            blue: output_color.encode_channel_split(r, g, b, 2),
        };
    }
    const adjusted = linear_chroma.apply(r, g, b, plan.linear_chroma);
    return {
        red: output_color.encode_channel_split(adjusted.red, adjusted.green, adjusted.blue, 0),
        green: output_color.encode_channel_split(adjusted.red, adjusted.green, adjusted.blue, 1),
        blue: output_color.encode_channel_split(adjusted.red, adjusted.green, adjusted.blue, 2),
    };
}

pub fn working_srgb_plan(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): WorkingSrgbPlan {
    return working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, 1.0);
}

pub fn working_srgb_plan_with_chroma(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): WorkingSrgbPlan {
    return {
        exposure_ev: exposure_ev,
        red_gain: red_gain,
        green_gain: green_gain,
        blue_gain: blue_gain,
        linear_chroma: chroma
    };
}
