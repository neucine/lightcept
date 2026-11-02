import .engine.raw.dng.dng_profile;
import .engine.color.working_rgb;

// DNG ForwardMatrix and as-shot neutral to linear Rec.2020/D65.
pub fn to_working(profile: dng_profile.CameraProfile, red: f64, green: f64, blue: f64): working_rgb.WorkingRgb {
    const r = red / profile.neutral_r;
    const g = green / profile.neutral_g;
    const b = blue / profile.neutral_b;
    const x50 = profile.m00 * r + profile.m01 * g + profile.m02 * b;
    const y50 = profile.m10 * r + profile.m11 * g + profile.m12 * b;
    const z50 = profile.m20 * r + profile.m21 * g + profile.m22 * b;
    return working_rgb.xyz_d50_to_working(x50, y50, z50);
}
