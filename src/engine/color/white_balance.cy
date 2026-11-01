// Relative working-space Rec.2020 channel gain, not camera sensor WB.
pub fn apply(value: f64, gain: f64): f64 {
    return value * gain;
}

// Camera AsShotNeutral reciprocal. The bridge validates finite neutral values
// in [0.05, 8] and narrows the result to its binary32 transport buffer.
pub export c("lc_cyna_img_v1_camera_neutral_gain") fn camera_neutral_gain(neutral: c_double): c_double {
    return (1.0 / (neutral as f64)) as c_double;
}
