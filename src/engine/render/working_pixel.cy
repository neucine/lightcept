import .engine.develop.exposure;
import .engine.develop.linear_chroma;
import .engine.develop.contrast;
import .engine.develop.shadows;
import .engine.develop.highlights;
import .engine.develop.black_point;
import .engine.develop.whites;
import .engine.develop.vibrance;
import .engine.color.relative_white;
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

// Preview tone order v1: exposure, shadows, contrast, highlights, output.
// Zero strengths preserve the established exposure/contrast encoder exactly.
pub fn encode_working_pixel_with_tone(red: f64, green: f64, blue: f64, plan: WorkingSrgbPlan, slope: f64, shadow_strength: f64, highlight_strength: f64): EncodedRgb {
    if shadow_strength == 0.0 and highlight_strength == 0.0 {
        return encode_working_pixel_with_contrast(red, green, blue, plan, slope);
    }
    const gain = output_color.exposure_gain(plan.exposure_ev);
    const exposed_red = exposure.apply(red, gain);
    const exposed_green = exposure.apply(green, gain);
    const exposed_blue = exposure.apply(blue, gain);
    const shadow = shadows.apply(exposed_red, exposed_green, exposed_blue, shadow_strength);
    const contrasted = contrast.apply(shadow.red, shadow.green, shadow.blue, slope);
    const highlight = highlights.apply(contrasted.red, contrasted.green, contrasted.blue, highlight_strength);
    return {
        red: output_color.encode_channel(highlight.red, highlight.green, highlight.blue, 0),
        green: output_color.encode_channel(highlight.red, highlight.green, highlight.blue, 1),
        blue: output_color.encode_channel(highlight.red, highlight.green, highlight.blue, 2)
    };
}

// Preview tone order v2: exposure, black offset, shadows, contrast,
// highlights, whites, output. Neutral endpoints preserve v1 exactly.
pub fn encode_working_pixel_with_endpoints(red: f64, green: f64, blue: f64, plan: WorkingSrgbPlan, slope: f64, black_offset: f64, shadow_strength: f64, highlight_strength: f64, white_strength: f64): EncodedRgb {
    if black_offset == 0.0 and white_strength == 0.0 {
        return encode_working_pixel_with_tone(red, green, blue, plan, slope, shadow_strength, highlight_strength);
    }
    const gain = output_color.exposure_gain(plan.exposure_ev);
    const black = black_point.apply(exposure.apply(red, gain), exposure.apply(green, gain), exposure.apply(blue, gain), black_offset);
    const shadow = shadows.apply(black.red, black.green, black.blue, shadow_strength);
    const contrasted = contrast.apply(shadow.red, shadow.green, shadow.blue, slope);
    const highlight = highlights.apply(contrasted.red, contrasted.green, contrasted.blue, highlight_strength);
    const white = whites.apply(highlight.red, highlight.green, highlight.blue, white_strength);
    return {
        red: output_color.encode_channel(white.red, white.green, white.blue, 0),
        green: output_color.encode_channel(white.red, white.green, white.blue, 1),
        blue: output_color.encode_channel(white.red, white.green, white.blue, 2)
    };
}

// Relative white and vibrance extend the pinned endpoint path. Neutral color
// values call that path directly, preserving all existing route-v1 bytes.
pub fn encode_working_pixel_with_color(red: f64, green: f64, blue: f64,
    plan: WorkingSrgbPlan, slope: f64, black_offset: f64,
    shadow_strength: f64, highlight_strength: f64, white_strength: f64,
    warmth_percent: i32, tint_percent: i32, vibrance_percent: i32,
    saturation_percent: i32
): EncodedRgb {
    if warmth_percent == 0 and tint_percent == 0 and vibrance_percent == 0 and saturation_percent == 0 {
        return encode_working_pixel_with_endpoints(red, green, blue, plan, slope,
            black_offset, shadow_strength, highlight_strength, white_strength
        );
    }
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const gains = relative_white.gains(warmth_percent, tint_percent);
    const balanced_red = exposure.apply(red, exposure_gain) * gains.red;
    const balanced_green = exposure.apply(green, exposure_gain) * gains.green;
    const balanced_blue = exposure.apply(blue, exposure_gain) * gains.blue;
    const black = black_point.apply(balanced_red, balanced_green, balanced_blue, black_offset);
    const shadow = shadows.apply(black.red, black.green, black.blue, shadow_strength);
    const contrasted = contrast.apply(shadow.red, shadow.green, shadow.blue, slope);
    const highlight = highlights.apply(contrasted.red, contrasted.green, contrasted.blue, highlight_strength);
    const white = whites.apply(highlight.red, highlight.green, highlight.blue, white_strength);
    const vibrant = vibrance.apply(white.red, white.green, white.blue, (vibrance_percent as f64) / 100.0);
    const saturated = linear_chroma.apply_native(vibrant.red, vibrant.green, vibrant.blue,
        1.0 + (saturation_percent as f64) / 100.0
    );
    return {
        red: output_color.encode_channel(saturated.red, saturated.green, saturated.blue, 0),
        green: output_color.encode_channel(saturated.red, saturated.green, saturated.blue, 1),
        blue: output_color.encode_channel(saturated.red, saturated.green, saturated.blue, 2)
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
