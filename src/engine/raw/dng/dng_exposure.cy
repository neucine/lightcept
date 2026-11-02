import .engine.tiff.tiff;

// DNG default exposure metadata. BaselineExposure is SRATIONAL, while
// BaselineExposureOffset is RATIONAL. Both are EV adjustments in root IFD.
// This product includes DNG technology under license by Adobe.
pub fn probe(input: *const u8, length: usize, output: *f64, output_len: usize): i32 {
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
    var marker = false;
    var baseline_seen = false;
    var offset_seen = false;
    var baseline: f64 = 0.0;
    var offset: f64 = 0.0;
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
        if tag == 50730 {
            if baseline_seen or kind != 10 or items != 1 or not tiff.has_range(size, value as usize, 8) {
                return 2;
            }
            const at = value as usize;
            const denominator = tiff.i32le(input, at + 4);
            if denominator == 0 {
                return 2;
            }
            baseline = tiff.i32le(input, at) as f64 / denominator as f64;
            baseline_seen = true;
        }
        if tag == 51109 {
            if offset_seen or kind != 5 or items != 1 or not tiff.has_range(size, value as usize, 8) {
                return 2;
            }
            const at = value as usize;
            const denominator = tiff.u32le(input, at + 4);
            if denominator == 0 {
                return 2;
            }
            offset = tiff.u32le(input, at) as f64 / denominator as f64;
            offset_seen = true;
        }
        index = index + 1;
    }
    if not marker {
        return 6;
    }
    if baseline < -16.0 or baseline > 16.0 or offset < 0.0 or offset > 16.0 or baseline + offset > 16.0 {
        return 2;
    }
    if output_len as usize != 3 {
        return 4;
    }
    write_double(output, 0, baseline);
    write_double(output, 1, offset);
    write_double(output, 2, baseline + offset);
    return 0;
}

fn write_double(output: *f64, index: usize, value: f64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *f64) = value as f64;
    }
}
