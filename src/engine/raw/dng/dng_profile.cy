import .engine.tiff.tiff;

// DNG ForwardMatrix1 maps white-balanced camera RGB to XYZ D50.
// AsShotNeutral supplies the camera-space neutral for that white balance.
// This product includes DNG technology under license by Adobe.

pub struct CameraProfile {
    pub m00: f64;
    pub m01: f64;
    pub m02: f64;
    pub m10: f64;
    pub m11: f64;
    pub m12: f64;
    pub m20: f64;
    pub m21: f64;
    pub m22: f64;
    pub neutral_r: f64;
    pub neutral_g: f64;
    pub neutral_b: f64;
    pub valid: bool;
}

// Camera characterization is stored in the root IFD even when the RAW image
// lives in a SubIFD. These are XYZ-to-camera matrices, not ForwardMatrix data.
// The caller must interpolate them by inverse correlated color temperature
// before constructing a camera-to-XYZ transform.
pub fn probe_color_matrices(input: *const u8, length: usize, output: *f64, output_len: usize): i32 {
    const size = length as usize;
    if not tiff.has_range(size, 0, 8) {
        return 1;
    }
    if tiff.byte(input, 0) != 73 or tiff.byte(input, 1) != 73 or tiff.u16le(input, 2) != 42 {
        return 6;
    }
    const root = tiff.u32le(input, 4) as usize;
    if not tiff.has_range(size, root, 2) {
        return 1;
    }
    const count = tiff.u16le(input, root) as usize;
    if count > 128 or not tiff.has_range(size, root + 2, count * 12 + 4) {
        return 1;
    }
    var matrix1: usize = 0;
    var matrix2: usize = 0;
    var neutral: usize = 0;
    var analog_balance: usize = 0;
    var unsupported_calibration = false;
    var illuminant1: u32 = 0;
    var illuminant2: u32 = 0;
    var marker = false;
    var index: usize = 0;
    while index < count {
        const base = root + 2 + index * 12;
        const tag = tiff.u16le(input, base);
        const kind = tiff.u16le(input, base + 2);
        const items = tiff.u32le(input, base + 4);
        const value = tiff.u32le(input, base + 8);
        if tag == 50706 and kind == 1 and items == 4 and value % 256 == 1 {
            marker = true;
        }
        if tag == 50721 and kind == 10 and items == 9 {
            matrix1 = value as usize;
        }
        if tag == 50722 and kind == 10 and items == 9 {
            matrix2 = value as usize;
        }
        if tag == 50728 and kind == 5 and items == 3 {
            neutral = value as usize;
        }
        if tag == 50727 {
            if kind != 5 or items != 3 {
                return 2;
            }
            analog_balance = value as usize;
        }
        if tag == 50723 or tag == 50724 or tag == 50933 or tag == 50934 or tag == 52529 or tag == 52530 {
            unsupported_calibration = true;
        }
        if tag == 50778 and kind == 3 and items == 1 {
            illuminant1 = value % 65536;
        }
        if tag == 50779 and kind == 3 and items == 1 {
            illuminant2 = value % 65536;
        }
        index = index + 1;
    }
    if not marker {
        return 6;
    }
    if matrix1 == 0 or matrix2 == 0 or neutral == 0 or illuminant1 == 0 or illuminant2 == 0 or unsupported_calibration {
        return 2;
    }
    if not tiff.has_range(size, matrix1, 72) or not tiff.has_range(size, matrix2, 72) or not tiff.has_range(size, neutral, 24) {
        return 1;
    }
    if analog_balance != 0 {
        if not tiff.has_range(size, analog_balance, 24) {
            return 1;
        }
        index = 0;
        while index < 3 {
            const at = analog_balance + index * 8;
            const denominator = tiff.u32le(input, at + 4);
            if denominator == 0 or tiff.u32le(input, at) != denominator {
                return 2;
            }
            index = index + 1;
        }
    }
    if output_len as usize != 23 {
        return 4;
    }
    index = 0;
    while index < 9 {
        const first = matrix1 + index * 8;
        const second = matrix2 + index * 8;
        if tiff.i32le(input, first + 4) == 0 or tiff.i32le(input, second + 4) == 0 {
            return 2;
        }
        write_double(output, index, signed_rational(input, first));
        write_double(output, 9 + index, signed_rational(input, second));
        index = index + 1;
    }
    index = 0;
    while index < 3 {
        const at = neutral + index * 8;
        if tiff.u32le(input, at + 4) == 0 {
            return 2;
        }
        const value = rational(input, at);
        if value <= 0.0 or value > 16.0 {
            return 2;
        }
        write_double(output, 18 + index, value);
        index = index + 1;
    }
    write_double(output, 21, illuminant1 as f64);
    write_double(output, 22, illuminant2 as f64);
    return 0;
}

fn write_double(output: *f64, index: usize, value: f64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *f64) = value as f64;
    }
}

fn signed_rational(input: *const u8, offset: usize): f64 {
    const denominator = tiff.i32le(input, offset + 4);
    return (tiff.i32le(input, offset) as f64) / (denominator as f64);
}

fn rational(input: *const u8, offset: usize): f64 {
    const denominator = tiff.u32le(input, offset + 4);
    return (tiff.u32le(input, offset) as f64) / (denominator as f64);
}

pub fn valid_denominators(input: *const u8, matrix_offset: usize, neutral_offset: usize): bool {
    var index: usize = 0;
    while index < 9 {
        if tiff.i32le(input, matrix_offset + index * 8 + 4) == 0 {
            return false;
        }
        index = index + 1;
    }
    index = 0;
    while index < 3 {
        if tiff.u32le(input, neutral_offset + index * 8 + 4) == 0 {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn load(input: *const u8, matrix_offset: usize, neutral_offset: usize): CameraProfile {
    var profile: CameraProfile = {
        m00: signed_rational(input, matrix_offset),
        m01: signed_rational(input, matrix_offset + 8),
        m02: signed_rational(input, matrix_offset + 16),
        m10: signed_rational(input, matrix_offset + 24),
        m11: signed_rational(input, matrix_offset + 32),
        m12: signed_rational(input, matrix_offset + 40),
        m20: signed_rational(input, matrix_offset + 48),
        m21: signed_rational(input, matrix_offset + 56),
        m22: signed_rational(input, matrix_offset + 64),
        neutral_r: rational(input, neutral_offset),
        neutral_g: rational(input, neutral_offset + 8),
        neutral_b: rational(input, neutral_offset + 16),
        valid: true,
    };
    if profile.neutral_r <= 0.0 or profile.neutral_r > 16.0 or profile.neutral_g <= 0.0 or profile.neutral_g > 16.0 or profile.neutral_b <= 0.0 or profile.neutral_b > 16.0 {
        profile.valid = false;
    }
    if profile.m00 < -16.0 or profile.m00 > 16.0 or profile.m01 < -16.0 or profile.m01 > 16.0 or profile.m02 < -16.0 or profile.m02 > 16.0 or profile.m10 < -16.0 or profile.m10 > 16.0 or profile.m11 < -16.0 or profile.m11 > 16.0 or profile.m12 < -16.0 or profile.m12 > 16.0 or profile.m20 < -16.0 or profile.m20 > 16.0 or profile.m21 < -16.0 or profile.m21 > 16.0 or profile.m22 < -16.0 or profile.m22 > 16.0 {
        profile.valid = false;
    }
    return profile;
}
