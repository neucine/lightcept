import std.math;
import .engine.core.core;

// Scene-linear Rec.2020/D65 radial lens correction v1. The caller supplies
// a characterized lens model and retains its profile/hash provenance.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct LensAsset {
    pub version: u32;
    pub model_hash: u64;
    pub center_x_fraction: f64;
    pub center_y_fraction: f64;
    pub k1: f64;
    pub boundary_fill: [3]f32;
}

pub struct MappedPoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

pub fn valid(asset: LensAsset): bool {
    if asset.version != algorithm_version or asset.model_hash == 0
    or not (asset.center_x_fraction >= 0.25 and asset.center_x_fraction <= 0.75)
    or not (asset.center_y_fraction >= 0.25 and asset.center_y_fraction <= 0.75)
    or not (asset.k1 >= -0.4 and asset.k1 <= 0.5) {
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

fn center_x(width: usize, asset: LensAsset): f64 {
    return ((width - 1) as f64) * asset.center_x_fraction;
}

fn center_y(height: usize, asset: LensAsset): f64 {
    return ((height - 1) as f64) * asset.center_y_fraction;
}

fn radius_scale(width: usize, height: usize, asset: LensAsset): f64 {
    const cx = center_x(width, asset);
    const cy = center_y(height, asset);
    var dx = cx;
    var dy = cy;
    if (width - 1) as f64 - cx > dx {
        dx = (width - 1) as f64 - cx;
    }
    if (height - 1) as f64 - cy > dy {
        dy = (height - 1) as f64 - cy;
    }
    return math.sqrt_f64(dx * dx + dy * dy);
}

fn distorted_radius(radius: f64, k1: f64): f64 {
    return radius * (1.0 - k1 + k1 * radius * radius);
}

fn corrected_radius(distorted: f64, k1: f64): f64 {
    var lower: f64 = 0.0;
    var upper: f64 = 1.0;
    var iteration: usize = 0;
    while iteration < 40 {
        const middle = (lower + upper) * 0.5;
        if distorted_radius(middle, k1) < distorted {
            lower = middle;
        } else {
            upper = middle;
        }
        iteration = iteration + 1;
    }
    return (lower + upper) * 0.5;
}

fn source_point(width: usize, height: usize,
    asset: LensAsset, x: f64, y: f64
): MappedPoint {
    const cx = center_x(width, asset);
    const cy = center_y(height, asset);
    const dx = x - cx;
    const dy = y - cy;
    const scale = radius_scale(width, height, asset);
    const radius = math.sqrt_f64(dx * dx + dy * dy) / scale;
    const factor = 1.0 - asset.k1 + asset.k1 * radius * radius;
    const mapped_x = cx + factor * dx;
    const mapped_y = cy + factor * dy;
    return {
        x: mapped_x,
        y: mapped_y,
        inside: mapped_x >= 0.0 and mapped_x <= (width - 1) as f64
        and mapped_y >= 0.0 and mapped_y <= (height - 1) as f64
    };
}

// Source distorted coordinates map to corrected output coordinates. The
// inverse radial solve uses 40 bisection steps on the monotonic [0,1] model.
pub fn map_source_point(width: usize, height: usize,
    asset: LensAsset, x: f64, y: f64
): MappedPoint {
    if not valid(asset) or width < 2 or height < 2
    or width > maximum_pixels or height > maximum_pixels / width
    or not (x >= 0.0 and x <= (width - 1) as f64)
    or not (y >= 0.0 and y <= (height - 1) as f64) {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const cx = center_x(width, asset);
    const cy = center_y(height, asset);
    const dx = x - cx;
    const dy = y - cy;
    const distance = math.sqrt_f64(dx * dx + dy * dy);
    if distance == 0.0 {
        return {
            x: cx,
            y: cy,
            inside: true
        };
    }
    const distorted = distance / radius_scale(width, height, asset);
    const corrected = corrected_radius(distorted, asset.k1);
    const factor = corrected / distorted;
    const mapped_x = cx + factor * dx;
    const mapped_y = cy + factor * dy;
    return {
        x: mapped_x,
        y: mapped_y,
        inside: mapped_x >= 0.0 and mapped_x <= (width - 1) as f64
        and mapped_y >= 0.0 and mapped_y <= (height - 1) as f64
    };
}

fn sample(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, channel: usize, asset: LensAsset
): ?f32 {
    if asset.k1 == 0.0 {
        return input[(y * width + x) * 3 + channel];
    }
    const point = source_point(width, height, asset, x as f64, y as f64);
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

// Immutable interleaved f32 RGB input and disjoint same-extent output.
// Bilinear sampling needs a one-pixel source halo. Status 0 success, 1 asset,
// 2 shape/limit, 3 nonfinite input, 4 nonfinite result, 7 cancelled. Any
// nonzero status invalidates output, including partial writes.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: LensAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width < 2 or height < 2 or width > maximum_pixels
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
