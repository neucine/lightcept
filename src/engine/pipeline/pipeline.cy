import .engine.develop.exposure;
import .engine.develop.linear_chroma;
import .engine.develop.contrast;
import .engine.color.white_balance;
import .engine.color.output_color;

pub struct EncodedRgb {
    pub red: c_double;
    pub green: c_double;
    pub blue: c_double;
}

// The first fixed headless develop plan. Cyna owns the order: exposure,
// working-space white balance, then the sRGB output transform. Rust passes
// validated buffers and parameters across the ABI, not stage definitions.
pub struct WorkingSrgbPlan {
    pub exposure_ev: c_double;
    pub red_gain: c_double;
    pub green_gain: c_double;
    pub blue_gain: c_double;
    pub linear_chroma: c_double;
}

pub fn working_srgb_plan(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double): WorkingSrgbPlan {
    return working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, 1.0);
}

pub fn working_srgb_plan_with_chroma(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double): WorkingSrgbPlan {
    return {
        exposure_ev: exposure_ev,
        red_gain: red_gain,
        green_gain: green_gain,
        blue_gain: blue_gain,
        linear_chroma: chroma
    };
}

pub fn encode_working_srgb_plan_pixel(red: c_float, green: c_float, blue: c_float, plan: WorkingSrgbPlan): EncodedRgb {
    return encode_working_pixel_with_chroma(red as c_double, green as c_double, blue as c_double, plan);
}

pub fn valid_working_plan_parameters(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double): bool {
    return valid_parameters(exposure_ev, red_gain, green_gain, blue_gain) and chroma >= working_chroma_min() and chroma <= working_chroma_max();
}

pub fn valid_contrast_plan_parameters(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double, slope: c_double): bool {
    return valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) and contrast.valid_slope(slope);
}

// Diagnostic v2 logical plan: exposure, working white, contrast, linear
// chroma, output. Existing v1 plan and render identities are unchanged.
export c("lc_cyna_img_v2_compile_working_srgb_plan") fn compile_working_srgb_contrast_plan(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double, slope: c_double, parameters: *c_double, parameters_len: c_size_t, stages: *c_uint, stages_len: c_size_t): c_int {
    if parameters_len as usize != 6 or stages_len as usize != 10 {
        return 3;
    }
    if not valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope) {
        return 4;
    }
    unchecked {
        *((parameters as! usize) as! *c_double) = exposure_ev;
        *(((parameters as! usize) + 8) as! *c_double) = red_gain;
        *(((parameters as! usize) + 16) as! *c_double) = green_gain;
        *(((parameters as! usize) + 24) as! *c_double) = blue_gain;
        *(((parameters as! usize) + 32) as! *c_double) = slope;
        *(((parameters as! usize) + 40) as! *c_double) = chroma;
        *((stages as! usize) as! *c_uint) = 1;
        *(((stages as! usize) + 4) as! *c_uint) = 1;
        *(((stages as! usize) + 8) as! *c_uint) = 2;
        *(((stages as! usize) + 12) as! *c_uint) = 1;
        *(((stages as! usize) + 16) as! *c_uint) = 5;
        *(((stages as! usize) + 20) as! *c_uint) = 1;
        *(((stages as! usize) + 24) as! *c_uint) = 3;
        *(((stages as! usize) + 28) as! *c_uint) = 1;
        *(((stages as! usize) + 32) as! *c_uint) = 4;
        *(((stages as! usize) + 36) as! *c_uint) = 1;
    }
    return 0;
}

pub fn encode_working_pixel_with_contrast(red: c_double, green: c_double, blue: c_double, plan: WorkingSrgbPlan, slope: c_double): EncodedRgb {
    if slope == 1.0 {
        return encode_working_pixel_with_chroma(red, green, blue, plan);
    }
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain as f64), plan.red_gain as f64) as c_double;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain as f64), plan.green_gain as f64) as c_double;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain as f64), plan.blue_gain as f64) as c_double;
    const toned = contrast.apply(r, g, b, slope);
    const adjusted = linear_chroma.apply(toned.red, toned.green, toned.blue, plan.linear_chroma);
    return {
        red: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 0),
        green: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 1),
        blue: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 2),
    };
}

// DNG BaselineExposure (including profile offset) moves the user control's
// zero point. Both inputs and the sum are validated by the render caller.
pub fn compose_exposure(default_ev: c_double, user_ev: c_double): c_double {
    return (default_ev as f64 + user_ev as f64) as c_double;
}

// Resolve a camera's default exposure and the user's edit before a working
// frame is rendered. The plan owner validates each control and their sum.
export c("lc_cyna_img_v1_resolve_working_exposure") fn resolve_working_exposure(default_ev: c_double, user_ev: c_double, output: *c_double, output_len: c_size_t): c_int {
    if output_len as usize != 1 {
        return 3;
    }
    const total = compose_exposure(default_ev, user_ev);
    if not valid_parameters(default_ev, 1.0, 1.0, 1.0) or not valid_parameters(user_ev, 1.0, 1.0, 1.0) or not valid_parameters(total, 1.0, 1.0, 1.0) {
        return 4;
    }
    unchecked {
        *(output as! *c_double) = total;
    }
    return 0;
}

// Fixed logical manifest: (stage id, algorithm version) for exposure,
// working white, linear chroma, and sRGB output. Parameters are copied in
// that order so a host can form a stable cache identity without defining the
// processing order itself. Status: 0 success, 3 shape, 4 parameters.
export c("lc_cyna_img_v1_compile_working_srgb_plan") fn compile_working_srgb_plan(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double, parameters: *c_double, parameters_len: c_size_t, stages: *c_uint, stages_len: c_size_t): c_int {
    if parameters_len as usize != 5 or stages_len as usize != 8 {
        return 3;
    }
    if not valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    unchecked {
        *((parameters as! usize) as! *c_double) = exposure_ev;
        *(((parameters as! usize) + 8) as! *c_double) = red_gain;
        *(((parameters as! usize) + 16) as! *c_double) = green_gain;
        *(((parameters as! usize) + 24) as! *c_double) = blue_gain;
        *(((parameters as! usize) + 32) as! *c_double) = chroma;
        *((stages as! usize) as! *c_uint) = 1;
        *(((stages as! usize) + 4) as! *c_uint) = 1;
        *(((stages as! usize) + 8) as! *c_uint) = 2;
        *(((stages as! usize) + 12) as! *c_uint) = 1;
        *(((stages as! usize) + 16) as! *c_uint) = 3;
        *(((stages as! usize) + 20) as! *c_uint) = 1;
        *(((stages as! usize) + 24) as! *c_uint) = 4;
        *(((stages as! usize) + 28) as! *c_uint) = 1;
    }
    return 0;
}

// Exposure is in stops (EV). White-balance gains are relative working-space
// Rec.2020 channel multipliers, not camera sensor coefficients.
// Declared as a whole number of stops: the Cyna compiler accepts only
// declarative, copy-valued top-level bindings (integers, bools, strings,
// structs), not floating-point globals. Bounds are exported as f64.
const working_exposure_limit_stops: i32 = 16;

pub fn working_exposure_min(): c_double {
    return -(working_exposure_limit_stops as f64) as c_double;
}

pub fn working_exposure_max(): c_double {
    return working_exposure_limit_stops as f64 as c_double;
}

pub fn working_gain_min(): c_double {
    return 0.125;
}
pub fn working_gain_max(): c_double {
    return 8.0;
}
pub fn working_chroma_min(): c_double {
    return 0.0;
}
pub fn working_chroma_max(): c_double {
    return 2.0;
}

// The exposure range a working develop plan accepts, in EV stops. A host that accumulates a
// develop state quotes these bounds; it never writes its own.
export c("lc_cyna_img_v1_working_exposure_bounds") fn working_exposure_bounds(output: *c_double, output_len: c_size_t): c_int {
    if output_len as usize != 2 {
        return 3;
    }
    unchecked {
        *(output as! *c_double) = working_exposure_min();
        *(((output as! usize) + 8) as! *c_double) = working_exposure_max();
    }
    return 0;
}

pub fn valid_parameters(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double): bool {
    const ev: f64 = exposure_ev as f64;
    const r: f64 = red_gain as f64;
    const g: f64 = green_gain as f64;
    const b: f64 = blue_gain as f64;
    return ev >= working_exposure_min() as f64 and ev <= working_exposure_max() as f64
    and r >= working_gain_min() as f64 and r <= working_gain_max() as f64
    and g >= working_gain_min() as f64 and g <= working_gain_max() as f64
    and b >= working_gain_min() as f64 and b <= working_gain_max() as f64;
}

pub fn encode_pixel(red: c_float, green: c_float, blue: c_float, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double): EncodedRgb {
    return encode_working_pixel(red as c_double, green as c_double, blue as c_double, exposure_ev, red_gain, green_gain, blue_gain);
}

pub fn encode_working_pixel(red: c_double, green: c_double, blue: c_double, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double): EncodedRgb {
    const ev: f64 = exposure_ev as f64;
    const exposure_gain: f64 = output_color.exposure_gain(ev as c_double) as f64;
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain), red_gain as f64) as c_double;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain), green_gain as f64) as c_double;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain), blue_gain as f64) as c_double;
    return {
        red: output_color.encode_channel(r, g, b, 0),
        green: output_color.encode_channel(r, g, b, 1),
        blue: output_color.encode_channel(r, g, b, 2),
    };
}

pub fn encode_working_pixel_with_chroma(red: c_double, green: c_double, blue: c_double, plan: WorkingSrgbPlan): EncodedRgb {
    if plan.linear_chroma == 1.0 {
        return encode_working_pixel(red, green, blue, plan.exposure_ev, plan.red_gain, plan.green_gain, plan.blue_gain);
    }
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain as f64), plan.red_gain as f64) as c_double;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain as f64), plan.green_gain as f64) as c_double;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain as f64), plan.blue_gain as f64) as c_double;
    const adjusted = linear_chroma.apply(r, g, b, plan.linear_chroma);
    return {
        red: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 0),
        green: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 1),
        blue: output_color.encode_channel(adjusted.red, adjusted.green, adjusted.blue, 2),
    };
}

// Diagnostic output branch: the same develop controls feed four explicit
// output operations. Stage ids 6..9 belong only to this new logical plan.
export c("lc_cyna_img_v1_compile_split_output_plan") fn compile_split_output_plan(exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double, parameters: *c_double, parameters_len: c_size_t, stages: *c_uint, stages_len: c_size_t): c_int {
    if parameters_len as usize != 5 or stages_len as usize != 14 {
        return 3;
    }
    if not valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    unchecked {
        *((parameters as! usize) as! *c_double) = exposure_ev;
        *(((parameters as! usize) + 8) as! *c_double) = red_gain;
        *(((parameters as! usize) + 16) as! *c_double) = green_gain;
        *(((parameters as! usize) + 24) as! *c_double) = blue_gain;
        *(((parameters as! usize) + 32) as! *c_double) = chroma;
        *((stages as! usize) as! *c_uint) = 1;
        *(((stages as! usize) + 4) as! *c_uint) = 1;
        *(((stages as! usize) + 8) as! *c_uint) = 2;
        *(((stages as! usize) + 12) as! *c_uint) = 1;
        *(((stages as! usize) + 16) as! *c_uint) = 3;
        *(((stages as! usize) + 20) as! *c_uint) = 1;
        *(((stages as! usize) + 24) as! *c_uint) = 6;
        *(((stages as! usize) + 28) as! *c_uint) = 1;
        *(((stages as! usize) + 32) as! *c_uint) = 7;
        *(((stages as! usize) + 36) as! *c_uint) = 1;
        *(((stages as! usize) + 40) as! *c_uint) = 8;
        *(((stages as! usize) + 44) as! *c_uint) = 1;
        *(((stages as! usize) + 48) as! *c_uint) = 9;
        *(((stages as! usize) + 52) as! *c_uint) = 1;
    }
    return 0;
}

pub fn encode_working_pixel_split(red: c_double, green: c_double, blue: c_double, plan: WorkingSrgbPlan): EncodedRgb {
    const exposure_gain = output_color.exposure_gain(plan.exposure_ev);
    const r = white_balance.apply(exposure.apply(red as f64, exposure_gain as f64), plan.red_gain as f64) as c_double;
    const g = white_balance.apply(exposure.apply(green as f64, exposure_gain as f64), plan.green_gain as f64) as c_double;
    const b = white_balance.apply(exposure.apply(blue as f64, exposure_gain as f64), plan.blue_gain as f64) as c_double;
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
