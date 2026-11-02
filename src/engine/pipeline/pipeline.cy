import .engine.render.working_pixel;
import .engine.develop.control_bounds;
import .engine.develop.exposure;

// The first fixed headless develop plan. Cyna owns the order: exposure,
// working-space white balance, then the sRGB output transform. Callers pass
// validated buffers and parameters; Cyna owns stage definitions.

// Diagnostic v2 logical plan: exposure, working white, contrast, linear
// chroma, output. Existing v1 plan and render identities are unchanged.
fn compile_working_srgb_contrast_plan(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, slope: f64, parameters: *f64, parameters_len: usize, stages: *u32, stages_len: usize): i32 {
    if parameters_len as usize != 6 or stages_len as usize != 10 {
        return 3;
    }
    if not valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope) {
        return 4;
    }
    unchecked {
        *((parameters as! usize) as! *f64) = exposure_ev;
        *(((parameters as! usize) + 8) as! *f64) = red_gain;
        *(((parameters as! usize) + 16) as! *f64) = green_gain;
        *(((parameters as! usize) + 24) as! *f64) = blue_gain;
        *(((parameters as! usize) + 32) as! *f64) = slope;
        *(((parameters as! usize) + 40) as! *f64) = chroma;
        *((stages as! usize) as! *u32) = 1;
        *(((stages as! usize) + 4) as! *u32) = 1;
        *(((stages as! usize) + 8) as! *u32) = 2;
        *(((stages as! usize) + 12) as! *u32) = 1;
        *(((stages as! usize) + 16) as! *u32) = 5;
        *(((stages as! usize) + 20) as! *u32) = 1;
        *(((stages as! usize) + 24) as! *u32) = 3;
        *(((stages as! usize) + 28) as! *u32) = 1;
        *(((stages as! usize) + 32) as! *u32) = 4;
        *(((stages as! usize) + 36) as! *u32) = 1;
    }
    return 0;
}

// DNG BaselineExposure (including profile offset) moves the user control's
// zero point. Both inputs and the sum are validated by the render caller.
pub fn working_srgb_plan(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): working_pixel.WorkingSrgbPlan {
    return working_pixel.working_srgb_plan(exposure_ev, red_gain, green_gain, blue_gain);
}
pub fn working_srgb_plan_with_chroma(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): working_pixel.WorkingSrgbPlan {
    return working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
}
pub fn valid_parameters(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): bool {
    return control_bounds.valid_parameters(exposure_ev, red_gain, green_gain, blue_gain);
}
pub fn valid_working_plan_parameters(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): bool {
    return control_bounds.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma);
}
pub fn valid_contrast_plan_parameters(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, slope: f64): bool {
    return control_bounds.valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope);
}

pub fn compose_exposure(default_ev: f64, user_ev: f64): f64 {
    return exposure.compose(default_ev, user_ev);
}

// Resolve a camera's default exposure and the user's edit before a working
// frame is rendered. The plan owner validates each control and their sum.
fn resolve_working_exposure(default_ev: f64, user_ev: f64, output: *f64, output_len: usize): i32 {
    if output_len as usize != 1 {
        return 3;
    }
    const total = compose_exposure(default_ev, user_ev);
    if not valid_parameters(default_ev, 1.0, 1.0, 1.0) or not valid_parameters(user_ev, 1.0, 1.0, 1.0) or not valid_parameters(total, 1.0, 1.0, 1.0) {
        return 4;
    }
    unchecked {
        *(output as! *f64) = total;
    }
    return 0;
}

// Fixed logical manifest: (stage id, algorithm version) for exposure,
// working white, linear chroma, and sRGB output. Parameters are copied in
// that order so a host can form a stable cache identity without defining the
// processing order itself. Status: 0 success, 3 shape, 4 parameters.
fn compile_working_srgb_plan(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, parameters: *f64, parameters_len: usize, stages: *u32, stages_len: usize): i32 {
    if parameters_len as usize != 5 or stages_len as usize != 8 {
        return 3;
    }
    if not valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    unchecked {
        *((parameters as! usize) as! *f64) = exposure_ev;
        *(((parameters as! usize) + 8) as! *f64) = red_gain;
        *(((parameters as! usize) + 16) as! *f64) = green_gain;
        *(((parameters as! usize) + 24) as! *f64) = blue_gain;
        *(((parameters as! usize) + 32) as! *f64) = chroma;
        *((stages as! usize) as! *u32) = 1;
        *(((stages as! usize) + 4) as! *u32) = 1;
        *(((stages as! usize) + 8) as! *u32) = 2;
        *(((stages as! usize) + 12) as! *u32) = 1;
        *(((stages as! usize) + 16) as! *u32) = 3;
        *(((stages as! usize) + 20) as! *u32) = 1;
        *(((stages as! usize) + 24) as! *u32) = 4;
        *(((stages as! usize) + 28) as! *u32) = 1;
    }
    return 0;
}

// Compatibility accessors for the composed working plan.
pub fn working_exposure_min(): f64 {
    return control_bounds.working_exposure_min();
}
pub fn working_exposure_max(): f64 {
    return control_bounds.working_exposure_max();
}
pub fn working_gain_min(): f64 {
    return control_bounds.working_gain_min();
}
pub fn working_gain_max(): f64 {
    return control_bounds.working_gain_max();
}
pub fn working_chroma_min(): f64 {
    return control_bounds.working_chroma_min();
}
pub fn working_chroma_max(): f64 {
    return control_bounds.working_chroma_max();
}

// The exposure range a working develop plan accepts, in EV stops. A host that accumulates a
// develop state quotes these bounds; it never writes its own.
fn working_exposure_bounds(output: *f64, output_len: usize): i32 {
    if output_len as usize != 2 {
        return 3;
    }
    unchecked {
        *(output as! *f64) = working_exposure_min();
        *(((output as! usize) + 8) as! *f64) = working_exposure_max();
    }
    return 0;
}

// Diagnostic output branch: the same develop controls feed four explicit
// output operations. Stage ids 6..9 belong only to this new logical plan.
fn compile_split_output_plan(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, parameters: *f64, parameters_len: usize, stages: *u32, stages_len: usize): i32 {
    if parameters_len as usize != 5 or stages_len as usize != 14 {
        return 3;
    }
    if not valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    unchecked {
        *((parameters as! usize) as! *f64) = exposure_ev;
        *(((parameters as! usize) + 8) as! *f64) = red_gain;
        *(((parameters as! usize) + 16) as! *f64) = green_gain;
        *(((parameters as! usize) + 24) as! *f64) = blue_gain;
        *(((parameters as! usize) + 32) as! *f64) = chroma;
        *((stages as! usize) as! *u32) = 1;
        *(((stages as! usize) + 4) as! *u32) = 1;
        *(((stages as! usize) + 8) as! *u32) = 2;
        *(((stages as! usize) + 12) as! *u32) = 1;
        *(((stages as! usize) + 16) as! *u32) = 3;
        *(((stages as! usize) + 20) as! *u32) = 1;
        *(((stages as! usize) + 24) as! *u32) = 6;
        *(((stages as! usize) + 28) as! *u32) = 1;
        *(((stages as! usize) + 32) as! *u32) = 7;
        *(((stages as! usize) + 36) as! *u32) = 1;
        *(((stages as! usize) + 40) as! *u32) = 8;
        *(((stages as! usize) + 44) as! *u32) = 1;
        *(((stages as! usize) + 48) as! *u32) = 9;
        *(((stages as! usize) + 52) as! *u32) = 1;
    }
    return 0;
}
