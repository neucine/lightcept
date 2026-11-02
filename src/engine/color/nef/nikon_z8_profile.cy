// Nikon Z8 lossless 14-bit candidate characterization v1. Camera2RGB is the
// LibRaw 0.22.2 reference matrix already reviewed in the Rust reference path
// (SHA-256 identity 7ec7454c9b072531fe487d6996ef9696446cf6b7a942a8e6ea68a445f643d39e).
// Input gains are dimensionless Nikon as-shot ratios relative to green.
// Output is row-major camera-linear RGB to XYZ D50, for the headless Cyna
// camera-to-working transform. No display encoding occurs in this component.

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
        1.39310085773, -0.215686887503, -0.177413955331,
        -0.136363446712, 1.47863578796, -0.342272281647,
        -0.0256121251732, -0.32102650404, 1.3466386795
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
