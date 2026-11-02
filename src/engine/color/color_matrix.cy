import .engine.color.working_rgb;

// Row-major camera RGB to XYZ D50, then linear Rec.2020/D65.
pub fn camera_to_working(matrix: [9]f64, red: f64, green: f64, blue: f64): working_rgb.WorkingRgb {
    const x = matrix[0] * red + matrix[1] * green + matrix[2] * blue;
    const y = matrix[3] * red + matrix[4] * green + matrix[5] * blue;
    const z = matrix[6] * red + matrix[7] * green + matrix[8] * blue;
    return working_rgb.xyz_d50_to_working(x, y, z);
}
