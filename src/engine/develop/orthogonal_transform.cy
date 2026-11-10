import .engine.core.core;

// User quarter turns and mirrors on upright scene-linear Rec.2020/D65 RGB.
// Codes 1..8 use the TIFF orientation coordinate maps, but this operation is
// independent of the camera's recorded orientation. Pixel centers are integer
// coordinates, x right and y down. No samples are interpolated or clipped.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 50000000;

pub struct Transform {
    pub version: u32;
    pub code: u32;
}

pub struct Extent {
    pub width: usize;
    pub height: usize;
    pub status: u32;
}

pub struct SourceRect {
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
    pub status: u32;
}

pub struct MappedPoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

pub fn valid(transform: Transform, width: usize, height: usize): bool {
    return transform.version == algorithm_version
    and transform.code >= 1 and transform.code <= 8
    and width > 0 and height > 0 and width <= maximum_pixels
    and height <= maximum_pixels / width;
}

pub fn extent(transform: Transform, width: usize, height: usize): Extent {
    if not valid(transform, width, height) {
        return {
            width: 0,
            height: 0,
            status: 1
        };
    }
    if transform.code >= 5 {
        return {
            width: height,
            height: width,
            status: 0
        };
    }
    return {
        width: width,
        height: height,
        status: 0
    };
}

// Exact upright source rectangle for a rectangle in the transformed canvas.
// Every pixel in that output rectangle is represented exactly once.
pub fn inverse_rect(transform: Transform, width: usize, height: usize,
    left: usize, top: usize, region_width: usize,
    region_height: usize
): SourceRect {
    const shape = extent(transform, width, height);
    if shape.status != 0 or left >= shape.width or top >= shape.height
    or region_width == 0 or region_height == 0
    or region_width > shape.width - left
    or region_height > shape.height - top {
        return {
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            status: 1
        };
    }
    if transform.code == 2 {
        return {
            left: width - left - region_width,
            top: top,
            width: region_width,
            height: region_height,
            status: 0
        };
    }
    if transform.code == 3 {
        return {
            left: width - left - region_width,
            top: height - top - region_height,
            width: region_width,
            height: region_height,
            status: 0
        };
    }
    if transform.code == 4 {
        return {
            left: left,
            top: height - top - region_height,
            width: region_width,
            height: region_height,
            status: 0
        };
    }
    if transform.code == 5 {
        return {
            left: top,
            top: left,
            width: region_height,
            height: region_width,
            status: 0
        };
    }
    if transform.code == 6 {
        return {
            left: top,
            top: height - left - region_width,
            width: region_height,
            height: region_width,
            status: 0
        };
    }
    if transform.code == 7 {
        return {
            left: width - top - region_height,
            top: height - left - region_width,
            width: region_height,
            height: region_width,
            status: 0
        };
    }
    if transform.code == 8 {
        return {
            left: width - top - region_height,
            top: left,
            width: region_height,
            height: region_width,
            status: 0
        };
    }
    return {
        left: left,
        top: top,
        width: region_width,
        height: region_height,
        status: 0
    };
}

// Source point to oriented output. The map is also valid for fractional mask
// coordinates inside the source pixel-center domain.
pub fn map_source_point(transform: Transform, width: usize, height: usize,
    x: f64, y: f64
): MappedPoint {
    if not valid(transform, width, height) or
    not (x >= 0.0 and x <= (width - 1) as f64) or
    not (y >= 0.0 and y <= (height - 1) as f64) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const right = (width - 1) as f64;
    const bottom = (height - 1) as f64;
    if transform.code == 2 {
        return {
            x: right - x,
            y: y,
            inside: true
        };
    }
    if transform.code == 3 {
        return {
            x: right - x,
            y: bottom - y,
            inside: true
        };
    }
    if transform.code == 4 {
        return {
            x: x,
            y: bottom - y,
            inside: true
        };
    }
    if transform.code == 5 {
        return {
            x: y,
            y: x,
            inside: true
        };
    }
    if transform.code == 6 {
        return {
            x: bottom - y,
            y: x,
            inside: true
        };
    }
    if transform.code == 7 {
        return {
            x: bottom - y,
            y: right - x,
            inside: true
        };
    }
    if transform.code == 8 {
        return {
            x: y,
            y: right - x,
            inside: true
        };
    }
    return {
        x: x,
        y: y,
        inside: true
    };
}

// Preserve the same source pixel centers when a user changes orientation.
// The returned rectangle is in the new transformed canvas. Straighten runs
// before either transform, so its angle does not change this exact mapping.
pub fn remap_rect(old_transform: Transform, new_transform: Transform,
    source_width: usize, source_height: usize, left: usize, top: usize,
    width: usize, height: usize
): SourceRect {
    const source = inverse_rect(old_transform, source_width, source_height,
        left, top, width, height
    );
    if source.status != 0 or not valid(new_transform, source_width, source_height) {
        return {
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            status: 1
        };
    }
    const first = map_source_point(new_transform, source_width, source_height,
        source.left as f64, source.top as f64
    );
    const last = map_source_point(new_transform, source_width, source_height,
        (source.left + source.width - 1) as f64,
        (source.top + source.height - 1) as f64
    );
    if not first.inside or not last.inside {
        return {
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            status: 1
        };
    }
    const x0 = first.x as usize;
    const x1 = last.x as usize;
    const y0 = first.y as usize;
    const y1 = last.y as usize;
    var minimum_x = x0;
    var minimum_y = y0;
    var maximum_x = x1;
    var maximum_y = y1;
    if x1 < x0 {
        minimum_x = x1;
        maximum_x = x0;
    }
    if y1 < y0 {
        minimum_y = y1;
        maximum_y = y0;
    }
    return {
        left: minimum_x,
        top: minimum_y,
        width: maximum_x - minimum_x + 1,
        height: maximum_y - minimum_y + 1,
        status: 0
    };
}

// Immutable interleaved f64 RGB input and disjoint exact-size output. Status
// 0 succeeds, 1 rejects transform/extent, 2 rejects buffer shapes, 3 rejects
// nonfinite input, and 7 reports cancellation. Output is invalid on failure.
// Cancellation is checked before each validation and output row.
pub fn apply_f64(input: []const f64, width: usize, height: usize,
    transform: Transform, output: []f64,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const shape = extent(transform, width, height);
    if shape.status != 0 {
        return 1;
    }
    return apply_region_f64(input, width, height, transform, 0, 0,
        shape.width, shape.height, output, cancelled, context
    );
}

// Select a rectangle in the transformed canvas without allocating a full
// transformed frame. Coordinates and dimensions are output pixels.
pub fn apply_region_f64(input: []const f64, width: usize, height: usize,
    transform: Transform, left: usize, top: usize,
    region_width: usize, region_height: usize, output: []f64,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const shape = extent(transform, width, height);
    if shape.status != 0 or left >= shape.width or top >= shape.height
    or region_width == 0 or region_height == 0
    or region_width > shape.width - left
    or region_height > shape.height - top {
        return 1;
    }
    if input.len() != width * height * 3 or
    output.len() != region_width * region_height * 3 {
        return 2;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var channel: usize = 0;
        while channel < width * 3 {
            if not core.finite_sample64(input[row * width * 3 + channel]) {
                return 3;
            }
            channel = channel + 1;
        }
        row = row + 1;
    }
    row = 0;
    while row < region_height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < region_width {
            const transformed_x = left + column;
            const transformed_y = top + row;
            var source_x = transformed_x;
            var source_y = transformed_y;
            if transform.code == 2 {
                source_x = width - 1 - transformed_x;
            }
            if transform.code == 3 {
                source_x = width - 1 - transformed_x;
                source_y = height - 1 - transformed_y;
            }
            if transform.code == 4 {
                source_y = height - 1 - transformed_y;
            }
            if transform.code == 5 {
                source_x = transformed_y;
                source_y = transformed_x;
            }
            if transform.code == 6 {
                source_x = transformed_y;
                source_y = height - 1 - transformed_x;
            }
            if transform.code == 7 {
                source_x = width - 1 - transformed_y;
                source_y = height - 1 - transformed_x;
            }
            if transform.code == 8 {
                source_x = width - 1 - transformed_y;
                source_y = transformed_x;
            }
            const source_offset = (source_y * width + source_x) * 3;
            const output_offset = (row * region_width + column) * 3;
            output[output_offset] = input[source_offset];
            output[output_offset + 1] = input[source_offset + 1];
            output[output_offset + 2] = input[source_offset + 2];
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
