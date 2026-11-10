import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 small-angle rotation v1. Positive radians rotate
// clockwise in image coordinates (x right, y down). Output keeps source extent.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 50000000;

pub struct StraightenAsset {
    pub version: u32;
    pub angle_radians: f64;
    pub boundary_fill: [3]f32;
}

pub struct MappedPoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

pub struct SourceWindow {
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
    pub status: u32;
}

pub fn valid(asset: StraightenAsset): bool {
    if asset.version != algorithm_version
    or not (asset.angle_radians >= -0.3 and asset.angle_radians <= 0.3) {
        return false;
    }
    var channel: usize = 0;
    while channel < 3 {
        if not core.finite_sample(asset.boundary_fill[channel]) {
            return false;
        }
        channel = channel + 1;
    }
    return true;
}

// Fixed polynomial, accurate for the declared ±0.3 radian range.
fn sine(angle: f64): f64 {
    const squared = angle * angle;
    return angle * (1.0 - squared / 6.0 + squared * squared / 120.0
        - squared * squared * squared / 5040.0
    );
}

fn cosine(angle: f64): f64 {
    const squared = angle * angle;
    return 1.0 - squared / 2.0 + squared * squared / 24.0
    - squared * squared * squared / 720.0
    + squared * squared * squared * squared / 40320.0;
}

pub fn map_source_point(width: usize, height: usize,
    asset: StraightenAsset, x: f64, y: f64
): MappedPoint {
    if not valid(asset) or width == 0 or height == 0
    or width > maximum_pixels or height > maximum_pixels / width
    or not (x >= 0.0 and x < width as f64)
    or not (y >= 0.0 and y < height as f64) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const cx = ((width - 1) as f64) * 0.5;
    const cy = ((height - 1) as f64) * 0.5;
    const dx = x - cx;
    const dy = y - cy;
    const mapped_x = cx + cosine(asset.angle_radians) * dx
    - sine(asset.angle_radians) * dy;
    const mapped_y = cy + sine(asset.angle_radians) * dx
    + cosine(asset.angle_radians) * dy;
    return {
        x: mapped_x,
        y: mapped_y,
        inside: mapped_x >= 0.0 and mapped_x <= (width - 1) as f64
        and mapped_y >= 0.0 and mapped_y <= (height - 1) as f64
    };
}

fn sample(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, channel: usize, asset: StraightenAsset
): ?f32 {
    if asset.angle_radians == 0.0 {
        return input[(y * width + x) * 3 + channel];
    }
    const cx = ((width - 1) as f64) * 0.5;
    const cy = ((height - 1) as f64) * 0.5;
    const dx = (x as f64) - cx;
    const dy = (y as f64) - cy;
    const source_x = cx + cosine(asset.angle_radians) * dx
    + sine(asset.angle_radians) * dy;
    const source_y = cy - sine(asset.angle_radians) * dx
    + cosine(asset.angle_radians) * dy;
    if (0.0 > source_x or 0.0 > source_y
        or source_x > ((width - 1) as f64)
        or source_y > ((height - 1) as f64)
    ) {
        return asset.boundary_fill[channel];
    }
    const x0 = source_x as usize;
    const y0 = source_y as usize;
    var x1 = x0;
    var y1 = y0;
    if x0 + 1 < width {
        x1 = x0 + 1;
    }
    if y0 + 1 < height {
        y1 = y0 + 1;
    }
    const fx = source_x - (x0 as f64);
    const fy = source_y - (y0 as f64);
    const upper = (1.0 - fx) * (input[(y0 * width + x0) * 3 + channel] as f64)
    + fx * (input[(y0 * width + x1) * 3 + channel] as f64);
    const lower = (1.0 - fx) * (input[(y1 * width + x0) * 3 + channel] as f64)
    + fx * (input[(y1 * width + x1) * 3 + channel] as f64);
    return math.to_f32_rounded((1.0 - fy) * upper + fy * lower);
}

fn sample_f64(input: []const f64, width: usize, height: usize,
    x: usize, y: usize, channel: usize, asset: StraightenAsset
): f64 {
    if asset.angle_radians == 0.0 {
        return input[(y * width + x) * 3 + channel];
    }
    const cx = ((width - 1) as f64) * 0.5;
    const cy = ((height - 1) as f64) * 0.5;
    const dx = (x as f64) - cx;
    const dy = (y as f64) - cy;
    const source_x = cx + cosine(asset.angle_radians) * dx
    + sine(asset.angle_radians) * dy;
    const source_y = cy - sine(asset.angle_radians) * dx
    + cosine(asset.angle_radians) * dy;
    if 0.0 > source_x or 0.0 > source_y or
    source_x > ((width - 1) as f64) or
    source_y > ((height - 1) as f64) {
        return asset.boundary_fill[channel] as f64;
    }
    const x0 = source_x as usize;
    const y0 = source_y as usize;
    var x1 = x0;
    var y1 = y0;
    if x0 + 1 < width {
        x1 = x0 + 1;
    }
    if y0 + 1 < height {
        y1 = y0 + 1;
    }
    const fx = source_x - (x0 as f64);
    const fy = source_y - (y0 as f64);
    const upper = (1.0 - fx) * input[(y0 * width + x0) * 3 + channel]
    + fx * input[(y0 * width + x1) * 3 + channel];
    const lower = (1.0 - fx) * input[(y1 * width + x0) * 3 + channel]
    + fx * input[(y1 * width + x1) * 3 + channel];
    return (1.0 - fy) * upper + fy * lower;
}

// Immutable interleaved f32 RGB input and disjoint same-extent output.
// Bilinear interpolation needs a one-pixel source halo; outside centers use
// explicit fill. Status 0 success, 1 asset, 2 shape/limit, 3 nonfinite input,
// 4 nonfinite output, 7 cancelled. Any nonzero status invalidates output.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: StraightenAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return 2;
    }
    var pass: usize = 0;
    while pass < 3 {
        var y: usize = 0;
        while y < height {
            if cancelled(context) {
                return 7;
            }
            var x: usize = 0;
            while x < width {
                const index = (y * width + x) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    if pass == 0 {
                        if not core.finite_sample(input[index + channel]) {
                            return 3;
                        }
                    } else {
                        const sampled = sample(input, width, height, x, y, channel, asset);
                        if sampled is value {
                            if pass == 1 {
                                if not core.finite_sample(value) {
                                    return 4;
                                }
                            } else {
                                output[index + channel] = value;
                            }
                        } else {
                            return 4;
                        }
                    }
                    channel = channel + 1;
                }
                x = x + 1;
            }
            y = y + 1;
        }
        pass = pass + 1;
    }
    return 0;
}

// Full-resolution f64 working RGB variant. Source and destination have the
// same upright extent and remain disjoint. Statuses and cancellation behavior
// match apply; output is invalid after any failure.
pub fn apply_f64(input: []const f64, width: usize, height: usize,
    asset: StraightenAsset, output: []f64,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels or
    height > maximum_pixels / width or
    input.len() != width * height * 3 or
    output.len() != input.len() {
        return 2;
    }
    var pass: usize = 0;
    while pass < 3 {
        var y: usize = 0;
        while y < height {
            if cancelled(context) {
                return 7;
            }
            var x: usize = 0;
            while x < width {
                const index = (y * width + x) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    if pass == 0 {
                        if not core.finite_sample64(input[index + channel]) {
                            return 3;
                        }
                    } else {
                        const value = sample_f64(input, width, height, x, y,
                            channel, asset
                        );
                        if pass == 1 {
                            if not core.finite_sample64(value) {
                                return 4;
                            }
                        } else {
                            output[index + channel] = value;
                        }
                    }
                    channel = channel + 1;
                }
                x = x + 1;
            }
            y = y + 1;
        }
        pass = pass + 1;
    }
    return 0;
}

// Render a rectangle of the full upright rotated canvas into disjoint
// scene-linear Rec.2020/D65 f64 output. Coordinates are source-canvas pixels;
// the interpolation and boundary fill match apply_f64 exactly. The caller
// owns the full input and only the requested output. Statuses are the same as
// apply_f64; a nonzero status invalidates output.
pub fn apply_region_f64(input: []const f64, width: usize, height: usize,
    asset: StraightenAsset, left: usize, top: usize,
    region_width: usize, region_height: usize, output: []f64,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels or
    height > maximum_pixels / width or
    input.len() != width * height * 3 or
    left >= width or top >= height or
    region_width == 0 or region_height == 0 or
    region_width > width - left or region_height > height - top or
    region_width > 4194304 / region_height or
    output.len() != region_width * region_height * 3 {
        return 2;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width * 3 {
            if not core.finite_sample64(input[row * width * 3 + column]) {
                return 3;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    var pass: usize = 0;
    while pass < 2 {
        row = 0;
        while row < region_height {
            if cancelled(context) {
                return 7;
            }
            var column: usize = 0;
            while column < region_width {
                var channel: usize = 0;
                while channel < 3 {
                    const value = sample_f64(input, width, height,
                        left + column, top + row, channel, asset
                    );
                    if pass == 0 {
                        if not core.finite_sample64(value) {
                            return 4;
                        }
                    } else {
                        output[(row * region_width + column) * 3 + channel] = value;
                    }
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}

// Conservative upright source rectangle for bilinear samples of a rotated
// output rectangle. The affine inverse reaches its extrema at the four
// corners. One extra sample at each far edge covers interpolation. Status 2
// means invalid geometry or a window above the 4,194,304-pixel limit.
pub fn source_window(width: usize, height: usize, asset: StraightenAsset,
    left: usize, top: usize, region_width: usize,
    region_height: usize
): SourceWindow {
    var result: SourceWindow = {
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        status: 2
    };
    if not valid(asset) {
        result.status = 1;
        return result;
    }
    if width == 0 or height == 0 or width > maximum_pixels or
    height > maximum_pixels / width or
    left >= width or top >= height or
    region_width == 0 or region_height == 0 or
    region_width > width - left or region_height > height - top or
    region_width > 4194304 / region_height {
        return result;
    }
    const cx = ((width - 1) as f64) * 0.5;
    const cy = ((height - 1) as f64) * 0.5;
    const sine_value = sine(asset.angle_radians);
    const cosine_value = cosine(asset.angle_radians);
    const xs: [2]usize = [left, left + region_width - 1];
    const ys: [2]usize = [top, top + region_height - 1];
    var minimum_x: f64 = width as f64;
    var minimum_y: f64 = height as f64;
    var maximum_x: f64 = -1.0;
    var maximum_y: f64 = -1.0;
    var row: usize = 0;
    while row < 2 {
        var column: usize = 0;
        while column < 2 {
            const dx = (xs[column] as f64) - cx;
            const dy = (ys[row] as f64) - cy;
            const source_x = cx + cosine_value * dx + sine_value * dy;
            const source_y = cy - sine_value * dx + cosine_value * dy;
            if source_x < minimum_x {
                minimum_x = source_x;
            }
            if source_x > maximum_x {
                maximum_x = source_x;
            }
            if source_y < minimum_y {
                minimum_y = source_y;
            }
            if source_y > maximum_y {
                maximum_y = source_y;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    var start_x: usize = 0;
    var start_y: usize = 0;
    var end_x = width;
    var end_y = height;
    if minimum_x > 0.0 {
        if minimum_x >= width as f64 {
            start_x = width - 1;
        } else {
            start_x = minimum_x as usize;
        }
    }
    if minimum_y > 0.0 {
        if minimum_y >= height as f64 {
            start_y = height - 1;
        } else {
            start_y = minimum_y as usize;
        }
    }
    if maximum_x < ((width - 1) as f64) {
        if maximum_x < 0.0 {
            end_x = 1;
        } else {
            end_x = (maximum_x as usize) + 2;
        }
    }
    if maximum_y < ((height - 1) as f64) {
        if maximum_y < 0.0 {
            end_y = 1;
        } else {
            end_y = (maximum_y as usize) + 2;
        }
    }
    if end_x <= start_x {
        end_x = start_x + 1;
    }
    if end_y <= start_y {
        end_y = start_y + 1;
    }
    const window_width = end_x - start_x;
    const window_height = end_y - start_y;
    if window_width > 4194304 / window_height {
        return result;
    }
    result.left = start_x;
    result.top = start_y;
    result.width = window_width;
    result.height = window_height;
    result.status = 0;
    return result;
}

fn sample_window_f64(input: []const f64, window: SourceWindow,
    width: usize, height: usize, x: usize, y: usize,
    channel: usize, asset: StraightenAsset
): ?f64 {
    const cx = ((width - 1) as f64) * 0.5;
    const cy = ((height - 1) as f64) * 0.5;
    const dx = (x as f64) - cx;
    const dy = (y as f64) - cy;
    const source_x = cx + cosine(asset.angle_radians) * dx
    + sine(asset.angle_radians) * dy;
    const source_y = cy - sine(asset.angle_radians) * dx
    + cosine(asset.angle_radians) * dy;
    if 0.0 > source_x or 0.0 > source_y or
    source_x > ((width - 1) as f64) or
    source_y > ((height - 1) as f64) {
        return asset.boundary_fill[channel] as f64;
    }
    const x0 = source_x as usize;
    const y0 = source_y as usize;
    var x1 = x0;
    var y1 = y0;
    if x0 + 1 < width {
        x1 = x0 + 1;
    }
    if y0 + 1 < height {
        y1 = y0 + 1;
    }
    if x0 < window.left or y0 < window.top or
    x1 >= window.left + window.width or
    y1 >= window.top + window.height {
        return none;
    }
    const fx = source_x - (x0 as f64);
    const fy = source_y - (y0 as f64);
    const local_x0 = x0 - window.left;
    const local_x1 = x1 - window.left;
    const local_y0 = y0 - window.top;
    const local_y1 = y1 - window.top;
    const upper = (1.0 - fx) * input[(local_y0 * window.width + local_x0) * 3 + channel]
    + fx * input[(local_y0 * window.width + local_x1) * 3 + channel];
    const lower = (1.0 - fx) * input[(local_y1 * window.width + local_x0) * 3 + channel]
    + fx * input[(local_y1 * window.width + local_x1) * 3 + channel];
    return (1.0 - fy) * upper + fy * lower;
}

// Render a rotated output rectangle from its source_window result. Input is
// scene-linear Rec.2020/D65 f64 for exactly that upright source window;
// output is disjoint. Status 2 includes a missing interpolation sample.
// Nonzero status invalidates output and cancellation is checked per row.
pub fn apply_window_region_f64(input: []const f64, width: usize,
    height: usize, asset: StraightenAsset, window: SourceWindow,
    left: usize, top: usize, region_width: usize, region_height: usize,
    output: []f64, cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if window.status != 0 or window.width == 0 or window.height == 0 or
    window.left >= width or window.top >= height or
    window.width > width - window.left or
    window.height > height - window.top or
    input.len() != window.width * window.height * 3 or
    left >= width or top >= height or
    region_width == 0 or region_height == 0 or
    region_width > width - left or region_height > height - top or
    region_width > 4194304 / region_height or
    output.len() != region_width * region_height * 3 {
        return 2;
    }
    var index: usize = 0;
    while index < input.len() {
        if cancelled(context) {
            return 7;
        }
        if not core.finite_sample64(input[index]) {
            return 3;
        }
        index = index + 1;
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < region_height {
            if cancelled(context) {
                return 7;
            }
            var column: usize = 0;
            while column < region_width {
                var channel: usize = 0;
                while channel < 3 {
                    const sample = sample_window_f64(input, window, width,
                        height, left + column, top + row, channel, asset
                    );
                    if sample is value {
                        if pass == 0 {
                            if not core.finite_sample64(value) {
                                return 4;
                            }
                        } else {
                            output[(row * region_width + column) * 3 + channel] = value;
                        }
                    } else {
                        return 2;
                    }
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
