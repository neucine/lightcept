import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 four-corner projective warp v1. The source
// quadrilateral is listed TL, TR, BR, BL and maps to output image corners.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct PerspectiveAsset {
    pub version: u32;
    pub source_corners: [8]f64;
    pub boundary_fill: [3]f32;
}

pub struct MappedPoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

struct Homography {
    a: f64;
    b: f64;
    c: f64;
    d: f64;
    e: f64;
    f: f64;
    g: f64;
    h: f64;
    valid: bool;
}

fn failed(): Homography {
    return {
        a: 0.0,
        b: 0.0,
        c: 0.0,
        d: 0.0,
        e: 0.0,
        f: 0.0,
        g: 0.0,
        h: 0.0,
        valid: false
    };
}

fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}

fn cross(corners: [8]f64, first: usize, second: usize, third: usize): f64 {
    const ax = corners[second * 2] - corners[first * 2];
    const ay = corners[second * 2 + 1] - corners[first * 2 + 1];
    const bx = corners[third * 2] - corners[second * 2];
    const by = corners[third * 2 + 1] - corners[second * 2 + 1];
    return ax * by - ay * bx;
}

fn matrix(asset: PerspectiveAsset, width: usize, height: usize): Homography {
    if asset.version != algorithm_version or width < 2 or height < 2
    or width > maximum_pixels or height > maximum_pixels / width {
        return failed();
    }
    var i: usize = 0;
    while i < 4 {
        const x = asset.source_corners[i * 2];
        const y = asset.source_corners[i * 2 + 1];
        if not (x >= 0.0 and x <= (width - 1) as f64)
        or not (y >= 0.0 and y <= (height - 1) as f64) {
            return failed();
        }
        i = i + 1;
    }
    i = 0;
    while i < 3 {
        if not core.finite_sample(asset.boundary_fill[i]) {
            return failed();
        }
        i = i + 1;
    }
    if cross(asset.source_corners, 0, 1, 2) <= 0.000001
    or cross(asset.source_corners, 1, 2, 3) <= 0.000001
    or cross(asset.source_corners, 2, 3, 0) <= 0.000001
    or cross(asset.source_corners, 3, 0, 1) <= 0.000001 {
        return failed();
    }
    const x00 = asset.source_corners[0];
    const y00 = asset.source_corners[1];
    const x10 = asset.source_corners[2];
    const y10 = asset.source_corners[3];
    const x11 = asset.source_corners[4];
    const y11 = asset.source_corners[5];
    const x01 = asset.source_corners[6];
    const y01 = asset.source_corners[7];
    const dx1 = x10 - x11;
    const dx2 = x01 - x11;
    const dx3 = x00 - x10 + x11 - x01;
    const dy1 = y10 - y11;
    const dy2 = y01 - y11;
    const dy3 = y00 - y10 + y11 - y01;
    var g: f64 = 0.0;
    var h: f64 = 0.0;
    if absolute(dx3) > 0.000000001 or absolute(dy3) > 0.000000001 {
        const determinant = dx1 * dy2 - dx2 * dy1;
        if absolute(determinant) <= 0.000000001 {
            return failed();
        }
        g = (dx3 * dy2 - dx2 * dy3) / determinant;
        h = (dx1 * dy3 - dx3 * dy1) / determinant;
    }
    if 1.0 + g <= 0.000001 or 1.0 + h <= 0.000001
    or 1.0 + g + h <= 0.000001 {
        return failed();
    }
    return {
        a: x10 - x00 + g * x10,
        b: x01 - x00 + h * x01,
        c: x00,
        d: y10 - y00 + g * y10,
        e: y01 - y00 + h * y01,
        f: y00,
        g: g,
        h: h,
        valid: true
    };
}

pub fn valid(asset: PerspectiveAsset, width: usize, height: usize): bool {
    return matrix(asset, width, height).valid;
}

fn source_point(transform: Homography, width: usize, height: usize,
    x: f64, y: f64
): MappedPoint {
    const u = x / ((width - 1) as f64);
    const v = y / ((height - 1) as f64);
    const denominator = transform.g * u + transform.h * v + 1.0;
    if denominator <= 0.000001 {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const mapped_x = (transform.a * u + transform.b * v + transform.c)
    / denominator;
    const mapped_y = (transform.d * u + transform.e * v + transform.f)
    / denominator;
    return {
        x: mapped_x,
        y: mapped_y,
        inside: mapped_x >= 0.0 and mapped_x <= (width - 1) as f64
        and mapped_y >= 0.0 and mapped_y <= (height - 1) as f64
    };
}

// Inverts the same four-corner transform for continuous source/mask points.
pub fn map_source_point(asset: PerspectiveAsset, width: usize,
    height: usize, x: f64, y: f64
): MappedPoint {
    const transform = matrix(asset, width, height);
    if not transform.valid or not (x >= 0.0 and x <= (width - 1) as f64)
    or not (y >= 0.0 and y <= (height - 1) as f64) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const aa = transform.a - x * transform.g;
    const bb = transform.b - x * transform.h;
    const dd = transform.d - y * transform.g;
    const ee = transform.e - y * transform.h;
    const determinant = aa * ee - bb * dd;
    if absolute(determinant) <= 0.000000001 {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const rhs_x = x - transform.c;
    const rhs_y = y - transform.f;
    const u = (rhs_x * ee - bb * rhs_y) / determinant;
    const v = (aa * rhs_y - rhs_x * dd) / determinant;
    return {
        x: u * ((width - 1) as f64),
        y: v * ((height - 1) as f64),
        inside: u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0
    };
}

fn sample(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, channel: usize,
    asset: PerspectiveAsset, transform: Homography
): ?f32 {
    const point = source_point(transform, width, height, x as f64, y as f64);
    if not point.inside {
        return asset.boundary_fill[channel];
    }
    const x0 = point.x as usize;
    const y0 = point.y as usize;
    var x1 = x0;
    var y1 = y0;
    if x0 + 1 < width {
        x1 = x0 + 1;
    }
    if y0 + 1 < height {
        y1 = y0 + 1;
    }
    const fx = point.x - (x0 as f64);
    const fy = point.y - (y0 as f64);
    const upper = (1.0 - fx) * (input[(y0 * width + x0) * 3 + channel] as f64)
    + fx * (input[(y0 * width + x1) * 3 + channel] as f64);
    const lower = (1.0 - fx) * (input[(y1 * width + x0) * 3 + channel] as f64)
    + fx * (input[(y1 * width + x1) * 3 + channel] as f64);
    return math.to_f32_rounded((1.0 - fy) * upper + fy * lower);
}

// Immutable interleaved f32 RGB input and disjoint same-size output. Bilinear
// sampling needs a one-pixel source halo. Status 0 success, 1 asset/geometry,
// 2 shape, 3 nonfinite input, 4 nonfinite result, 7 cancelled. Any nonzero
// status invalidates output, including partial writes after cancellation.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: PerspectiveAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const transform = matrix(asset, width, height);
    if not transform.valid {
        return 1;
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
                        const sampled = sample(input, width, height, x, y,
                            channel, asset, transform
                        );
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
