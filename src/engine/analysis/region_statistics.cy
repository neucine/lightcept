import .engine.core.core;

// Scene-linear Rec.2020/D65 region statistics v1. Coordinates are in the
// supplied image's unrotated pixel grid. The rectangle is half-open.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct Region {
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
}

pub struct Statistics {
    // 0 success, 1 image shape/limit, 2 region, 3 invalid sample, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub pixels: usize;
    pub mean_red: f64;
    pub mean_green: f64;
    pub mean_blue: f64;
    pub mean_y: f64;
    pub minimum_y: f64;
    pub maximum_y: f64;
}

fn failure(status: u32): Statistics {
    return {
        status: status,
        version: algorithm_version,
        pixels: 0,
        mean_red: 0.0,
        mean_green: 0.0,
        mean_blue: 0.0,
        mean_y: 0.0,
        minimum_y: 0.0,
        maximum_y: 0.0
    };
}

// Input is immutable, interleaved f32 RGB. Whole-image and region areas must
// each fit maximum_pixels; sum uses f64. Poll once per row. No result is usable
// unless status is zero. A rejected or cancelled call returns no measurements.
pub fn measure(input: []const f32, image_width: usize, image_height: usize,
    region: Region, cancelled: fn (usize): bool, context: usize
): Statistics {
    if image_width == 0 or image_height == 0 or image_width > maximum_pixels
    or image_height > maximum_pixels / image_width {
        return failure(1);
    }
    const image_pixels = image_width * image_height;
    if input.len() != image_pixels * 3 {
        return failure(1);
    }
    if region.width == 0 or region.height == 0 or region.left >= image_width
    or region.top >= image_height or region.width > image_width - region.left
    or region.height > image_height - region.top {
        return failure(2);
    }
    var sum_red: f64 = 0.0;
    var sum_green: f64 = 0.0;
    var sum_blue: f64 = 0.0;
    var minimum_y: f64 = 0.0;
    var maximum_y: f64 = 0.0;
    var row: usize = 0;
    while row < region.height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < region.width {
            const index = ((region.top + row) * image_width + region.left + column) * 3;
            const red = input[index];
            const green = input[index + 1];
            const blue = input[index + 2];
            if not (core.finite_sample(red) and red >= -0.25 and red <= 8.0
                and core.finite_sample(green) and green >= -0.25 and green <= 8.0
                and core.finite_sample(blue) and blue >= -0.25 and blue <= 8.0
            ) {
                return failure(3);
            }
            const r = red as f64;
            const g = green as f64;
            const b = blue as f64;
            const y = 0.2627 * r + 0.6780 * g + 0.0593 * b;
            if row == 0 and column == 0 {
                minimum_y = y;
                maximum_y = y;
            } else {
                if y < minimum_y {
                    minimum_y = y;
                }
                if y > maximum_y {
                    maximum_y = y;
                }
            }
            sum_red = sum_red + r;
            sum_green = sum_green + g;
            sum_blue = sum_blue + b;
            column = column + 1;
        }
        row = row + 1;
    }
    const pixels = region.width * region.height;
    const count = pixels as f64;
    const mean_red = sum_red / count;
    const mean_green = sum_green / count;
    const mean_blue = sum_blue / count;
    return {
        status: 0,
        version: algorithm_version,
        pixels: pixels,
        mean_red: mean_red,
        mean_green: mean_green,
        mean_blue: mean_blue,
        mean_y: 0.2627 * mean_red + 0.6780 * mean_green + 0.0593 * mean_blue,
        minimum_y: minimum_y,
        maximum_y: maximum_y
    };
}
