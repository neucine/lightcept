import .engine.develop.edit_plan;
import .engine.develop.exposure;
import .engine.develop.black_point;
import .engine.develop.shadows;
import .engine.develop.contrast;
import .engine.develop.highlights;
import .engine.develop.whites;
import .engine.develop.linear_chroma;
import .engine.develop.vibrance;
import .engine.develop.tone_curve;
import .engine.develop.channel_mixer;
import .engine.color.output_color;

// Diagnostic scalar executor for the logical develop plan. Input and output
// are signed scene-linear Rec.2020/D65 RGB. No clipping or output encoding.
pub struct SampleRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub struct SampleResult {
    pub valid: bool;
    // 0 success, 1 invalid plan, 2 nonfinite input, 3 nonfinite stage output,
    // 4 invalid optional curve asset, 5 nonfinite optional curve output,
    // 6 invalid optional mixer asset, 7 nonfinite optional mixer output.
    pub status: u32;
    pub pixel: SampleRgb;
}

fn finite(value: f64): bool {
    const infinity = output_color.exposure_gain_native(1024.0);
    return value > -infinity and value < infinity;
}

pub fn valid_plan(plan: edit_plan.DevelopPlan): bool {
    return plan.version == edit_plan.plan_version
    and plan.exposure_ev >= edit_plan.exposure_min()
    and plan.exposure_ev <= edit_plan.exposure_max()
    and black_point.valid_offset(plan.black_offset)
    and shadows.valid_strength(plan.shadows_strength)
    and plan.contrast_percent >= -100.0 and plan.contrast_percent <= 100.0
    and plan.contrast_slope == contrast.slope_from_percent_native(plan.contrast_percent)
    and highlights.valid_strength(plan.highlights_strength)
    and whites.valid_strength(plan.whites_strength)
    and plan.linear_chroma >= edit_plan.chroma_min()
    and plan.linear_chroma <= edit_plan.chroma_max()
    and vibrance.valid_strength(plan.vibrance_strength);
}

fn failure(status: u32): SampleResult {
    return {
        valid: false,
        status: status,
        pixel: {
            red: 0.0,
            green: 0.0,
            blue: 0.0
        }
    };
}

fn finite_pixel(pixel: SampleRgb): bool {
    return finite(pixel.red) and finite(pixel.green) and finite(pixel.blue);
}

pub fn apply(plan: edit_plan.DevelopPlan, input: SampleRgb): SampleResult {
    if not valid_plan(plan) {
        return failure(1);
    }
    if not finite_pixel(input) {
        return failure(2);
    }
    const gain = output_color.exposure_gain_native(plan.exposure_ev);
    var pixel: SampleRgb = {
        red: exposure.apply(input.red, gain),
        green: exposure.apply(input.green, gain),
        blue: exposure.apply(input.blue, gain)
    };
    if not finite_pixel(pixel) {
        return failure(3);
    }
    const black = black_point.apply(pixel.red, pixel.green, pixel.blue, plan.black_offset);
    pixel = {
        red: black.red,
        green: black.green,
        blue: black.blue
    };
    const shadow = shadows.apply(pixel.red, pixel.green, pixel.blue, plan.shadows_strength);
    pixel = {
        red: shadow.red,
        green: shadow.green,
        blue: shadow.blue
    };
    const contrasted = contrast.apply_native(pixel.red, pixel.green, pixel.blue, plan.contrast_slope);
    pixel = {
        red: contrasted.red,
        green: contrasted.green,
        blue: contrasted.blue
    };
    const highlight = highlights.apply(pixel.red, pixel.green, pixel.blue, plan.highlights_strength);
    pixel = {
        red: highlight.red,
        green: highlight.green,
        blue: highlight.blue
    };
    const white = whites.apply(pixel.red, pixel.green, pixel.blue, plan.whites_strength);
    pixel = {
        red: white.red,
        green: white.green,
        blue: white.blue
    };
    const chroma = linear_chroma.apply_native(pixel.red, pixel.green, pixel.blue, plan.linear_chroma);
    pixel = {
        red: chroma.red,
        green: chroma.green,
        blue: chroma.blue
    };
    const vibrant = vibrance.apply(pixel.red, pixel.green, pixel.blue, plan.vibrance_strength);
    pixel = {
        red: vibrant.red,
        green: vibrant.green,
        blue: vibrant.blue
    };
    if not finite_pixel(pixel) {
        return failure(3);
    }
    return {
        valid: true,
        status: 0,
        pixel: pixel
    };
}

// The optional curve is a separate asset, applied after every scalar control.
// It has no persisted identity or product route in this diagnostic contract.
pub fn apply_with_curve(plan: edit_plan.DevelopPlan, curve: tone_curve.CurveAsset, input: SampleRgb): SampleResult {
    const base = apply(plan, input);
    if not base.valid {
        return base;
    }
    const curved = tone_curve.apply(curve, base.pixel.red, base.pixel.green, base.pixel.blue);
    if not curved.valid {
        if curved.status == 1 {
            return failure(4);
        }
        return failure(5);
    }
    return {
        valid: true,
        status: 0,
        pixel: {
            red: curved.red,
            green: curved.green,
            blue: curved.blue
        }
    };
}

// Asset order is fixed: scalar controls, channel mixer, then tone curve.
pub fn apply_with_assets(plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: tone_curve.CurveAsset, input: SampleRgb): SampleResult {
    const base = apply(plan, input);
    if not base.valid {
        return base;
    }
    const mixed = channel_mixer.apply(mixer, base.pixel.red, base.pixel.green, base.pixel.blue);
    if not mixed.valid {
        if mixed.status == 1 {
            return failure(6);
        }
        return failure(7);
    }
    const curved = tone_curve.apply(curve, mixed.red, mixed.green, mixed.blue);
    if not curved.valid {
        if curved.status == 1 {
            return failure(4);
        }
        return failure(5);
    }
    return {
        valid: true,
        status: 0,
        pixel: {
            red: curved.red,
            green: curved.green,
            blue: curved.blue
        }
    };
}
