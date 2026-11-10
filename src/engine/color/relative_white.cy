// Relative white balance on an as-shot scene-linear Rec.2020/D65 working frame.
// Warmth and tint are signed percentages, not calibrated Kelvin or sensor gains.
// Neutral zero is exact identity. This operation belongs after exposure and
// before tonal and chroma edits in the ColorPreviewV1 route.
pub const algorithm_version: u32 = 1;

pub struct Gains {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn valid(warmth_percent: i32, tint_percent: i32): bool {
    return warmth_percent >= -100 and warmth_percent <= 100
    and tint_percent >= -100 and tint_percent <= 100;
}

// Positive warmth increases red and decreases blue. Positive tint shifts
// green toward magenta. Every gain remains in [0.375, 1.875].
pub fn gains(warmth_percent: i32, tint_percent: i32): Gains {
    const warmth = (warmth_percent as f64) / 200.0;
    const tint = (tint_percent as f64) / 200.0;
    const magenta = 1.0 + tint / 2.0;
    return {
        red: (1.0 + warmth) * magenta,
        green: 1.0 - tint,
        blue: (1.0 - warmth) * magenta
    };
}
