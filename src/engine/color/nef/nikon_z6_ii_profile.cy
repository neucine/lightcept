// Nikon Z6 II packed 14-bit characterization v1. Camera2RGB is LibRaw 0.22.2's
// camera-to-sRGB matrix for Nikon "Z 6"/"Z 6_2". Input gains are dimensionless
// Nikon as-shot ratios relative to green. Output is row-major camera-linear
// RGB to XYZ D50; no display encoding occurs in this component.

fn multiply(left: [9]f64, right: [9]f64): [9]f64 {
    var result: [9]f64 = [0.0] ** 9;
    var row: usize = 0;
    while row < 3 {
        var column: usize = 0;
        while column < 3 {
            var sum: f64 = 0.0;
            var inner: usize = 0;
            while inner < 3 {
                sum = sum + left[row * 3 + inner] * right[inner * 3 + column];
                inner = inner + 1;
            }
            result[row * 3 + column] = sum;
            column = column + 1;
        }
        row = row + 1;
    }
    return result;
}

pub fn camera_to_xyz_d50(red_gain: f64, blue_gain: f64): ?[9]f64 {
    if not (red_gain >= 0.05 and red_gain <= 8.0 and blue_gain >= 0.05 and blue_gain <= 8.0) {
        return none;
    }
    const camera_to_srgb: [9]f64 = [
        1.5967088273, -0.4041150815, -0.1925937459,
        -0.1410094230, 1.5044679585, -0.3634585355,
        0.0175678207, -0.4094387810, 1.3918709603
    ];
    const srgb_to_xyz: [9]f64 = [
        0.4123907992659593, 0.357584339383878, 0.1804807884018343,
        0.2126390058715102, 0.715168678767756, 0.07219231536073371,
        0.01933081871559185, 0.11919477979462598, 0.9505321522496607
    ];
    const d65_to_d50: [9]f64 = [
        1.0478112, 0.0228866, -0.050127,
        0.0295424, 0.9904844, -0.0170491,
        -0.0092345, 0.0150436, 0.7521316
    ];
    const white: [9]f64 = [red_gain, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, blue_gain];
    const result = multiply(multiply(d65_to_d50, srgb_to_xyz), multiply(camera_to_srgb, white));
    var index: usize = 0;
    while index < 9 {
        if result[index] != result[index] or result[index] < -32.0 or result[index] > 32.0 {
            return none;
        }
        index = index + 1;
    }
    return result;
}
