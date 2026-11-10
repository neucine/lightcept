// Interleaved, signed scene-linear Rec.2020/D65 RGB; three f32 samples per pixel.
// The caller owns storage. Dimensions and lengths are checked before any access.
pub fn validate_image(width: usize, height: usize, max_pixels: usize, input_len: usize, output_len: usize): i32 {
    if width == 0 or height == 0 {
        return 1;
    }
    if max_pixels == 0 or width > max_pixels / height {
        return 2;
    }
    const pixels = width * height;
    if pixels > 16777216 {
        return 2;
    }
    if input_len != pixels * 3 or output_len != pixels * 4 {
        return 3;
    }
    return 0;
}

pub fn validate_rgb16_image(width: usize, height: usize, max_pixels: usize, input_len: usize, output_len: usize): i32 {
    if width == 0 or height == 0 {
        return 1;
    }
    if max_pixels == 0 or width > max_pixels / height {
        return 2;
    }
    const pixels = width * height;
    if pixels > 16777216 {
        return 2;
    }
    if input_len != pixels * 3 or output_len != pixels * 3 {
        return 3;
    }
    return 0;
}

pub fn finite_sample(value: f32): bool {
    if value != value {
        return false;
    }
    const sample: f64 = value as f64;
    if sample >= 340282350000000000000000000000000000000.0 {
        return false;
    }
    if sample < 0.0 and -sample >= 340282350000000000000000000000000000000.0 {
        return false;
    }
    return true;
}

// IEEE subtraction of a finite value from itself is zero; NaN and infinities
// produce NaN. This avoids a native math dependency at the component boundary.
pub fn finite_sample64(value: f64): bool {
    return value - value == 0.0;
}
