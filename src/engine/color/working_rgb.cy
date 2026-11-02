pub struct WorkingRgb {
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn xyz_d50_to_working(x50: f64, y50: f64, z50: f64): WorkingRgb {
    // Bradford D50 -> D65, followed by XYZ D65 -> linear Rec.2020.
    // Universal color-space matrices from W3C CSS Color 4 conversion code.
    const x65 = 0.9555766 * x50 - 0.0230393 * y50 + 0.0631636 * z50;
    const y65 = -0.0282895 * x50 + 1.0099416 * y50 + 0.0210077 * z50;
    const z65 = 0.0122982 * x50 - 0.0204830 * y50 + 1.3299098 * z50;
    return {
        red: (1.7166511879712674 * x65 - 0.35567078377639233 * y65 - 0.25336628137365974 * z65) as f64,
        green: (-0.6666843518324892 * x65 + 1.6164812366349395 * y65 + 0.01576854581391113 * z65) as f64,
        blue: (0.017639857445310783 * x65 - 0.042770613257808524 * y65 + 0.9421031212354738 * z65) as f64,
    };
}
