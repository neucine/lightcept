// Signed scene-linear exposure multiplication; gain = 2^EV.
pub fn apply(value: f64, gain: f64): f64 {
    return value * gain;
}
