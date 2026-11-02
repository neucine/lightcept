import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 small-angle rotation v1. Positive radians rotate
// clockwise in image coordinates (x right, y down). Output keeps source extent.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

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
