import .engine.core.core;

// Scene-linear Rec.2020/D65 integer crop v1. Pixel centers retain their
// source values exactly. The caller keeps the uncropped source immutable.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct CropRect {
    pub version: u32;
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
}

pub struct MappedPoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

pub fn valid(rect: CropRect, source_width: usize, source_height: usize): bool {
    if rect.version != algorithm_version or source_width == 0
    or source_height == 0 or source_width > maximum_pixels
    or source_height > maximum_pixels / source_width
    or rect.width == 0 or rect.height == 0
    or rect.left >= source_width or rect.top >= source_height {
        return false;
    }
    return rect.width <= source_width - rect.left
    and rect.height <= source_height - rect.top;
}

// Continuous point coordinates have pixel centers at integer locations.
// Source (left, top) becomes output (0, 0). Points outside the output extent
// are marked outside so a caller can discard or clip associated masks.
pub fn map_source_point(rect: CropRect, source_width: usize,
    source_height: usize, x: f64, y: f64
): MappedPoint {
    if not valid(rect, source_width, source_height)
    or not (x >= 0.0 and x < source_width as f64)
    or not (y >= 0.0 and y < source_height as f64) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const mapped_x = x - (rect.left as f64);
    const mapped_y = y - (rect.top as f64);
    return {
        x: mapped_x,
        y: mapped_y,
        inside: mapped_x >= 0.0 and mapped_x < rect.width as f64
        and mapped_y >= 0.0 and mapped_y < rect.height as f64
    };
}

// Immutable interleaved f32 RGB input, disjoint output with exactly
// rect.width * rect.height pixels. Status 0 success, 1 invalid rect,
// 2 source/output shape, 3 nonfinite input, 7 cancelled. Every row is
// polled in validation and copy passes. On failure output is invalid.
pub fn apply(input: []const f32, source_width: usize, source_height: usize,
    rect: CropRect, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(rect, source_width, source_height) {
        return 1;
    }
    const source_pixels = source_width * source_height;
    const output_pixels = rect.width * rect.height;
    if input.len() != source_pixels * 3 or output.len() != output_pixels * 3 {
        return 2;
    }
    var row: usize = 0;
    while row < source_height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < source_width {
            const index = (row * source_width + column) * 3;
            var channel: usize = 0;
            while channel < 3 {
                if not core.finite_sample(input[index + channel]) {
                    return 3;
                }
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    row = 0;
    while row < rect.height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < rect.width {
            const source_index = ((rect.top + row) * source_width + rect.left + column) * 3;
            const output_index = (row * rect.width + column) * 3;
            output[output_index] = input[source_index];
            output[output_index + 1] = input[source_index + 1];
            output[output_index + 2] = input[source_index + 2];
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
