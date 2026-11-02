import .engine.develop.contrast;

// Exposure is in stops (EV). White-balance gains are relative working-space
// Rec.2020 channel multipliers, not camera sensor coefficients.
// Declared as a whole number of stops: the Cyna compiler accepts only
// declarative, copy-valued top-level bindings (integers, bools, strings,
// structs), not floating-point globals. Bounds are exported as f64.
const working_exposure_limit_stops: i32 = 16;

pub fn working_exposure_min(): f64 {
    return -(working_exposure_limit_stops as f64) as f64;
}

pub fn working_exposure_max(): f64 {
    return working_exposure_limit_stops as f64 as f64;
}

pub fn working_gain_min(): f64 {
    return 0.125;
}
pub fn working_gain_max(): f64 {
    return 8.0;
}
pub fn working_chroma_min(): f64 {
    return 0.0;
}
pub fn working_chroma_max(): f64 {
    return 2.0;
}

pub fn valid_working_plan_parameters(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): bool {
    return valid_parameters(exposure_ev, red_gain, green_gain, blue_gain) and chroma >= working_chroma_min() and chroma <= working_chroma_max();
}

pub fn valid_contrast_plan_parameters(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, slope: f64): bool {
    return valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) and contrast.valid_slope(slope);
}

pub fn valid_parameters(exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): bool {
    const ev: f64 = exposure_ev as f64;
    const r: f64 = red_gain as f64;
    const g: f64 = green_gain as f64;
    const b: f64 = blue_gain as f64;
    return ev >= working_exposure_min() as f64 and ev <= working_exposure_max() as f64
    and r >= working_gain_min() as f64 and r <= working_gain_max() as f64
    and g >= working_gain_min() as f64 and g <= working_gain_max() as f64
    and b >= working_gain_min() as f64 and b <= working_gain_max() as f64;
}
