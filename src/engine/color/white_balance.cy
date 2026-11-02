// Relative working-space Rec.2020 channel gain, not camera sensor WB.
pub fn apply(value: f64, gain: f64): f64 {
    return value * gain;
}

// Camera AsShotNeutral reciprocal. Callers validate finite neutral values
// in [0.05, 8] before applying the gain to camera samples.
pub fn camera_neutral_gain(neutral: f64): f64 {
    return 1.0 / neutral;
}
