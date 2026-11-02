import .engine.core.core;
import std.math;

// Camera-linear normalized Bayer mosaic TCA correction v1. Red and blue
// photosites are shifted radially relative to the unchanged green lattice.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct TcaAsset {
    pub version: u32;
    pub model_hash: u64;
    pub cfa: [4]u32;
    pub center_x_fraction: f64;
    pub center_y_fraction: f64;
    pub red_k1: f64;
    pub blue_k1: f64;
    pub maximum_change: f64;
    pub boundary_fill: [3]f32;
}

pub struct SamplePoint {
    pub x: f64;
    pub y: f64;
    pub inside: bool;
}

pub fn valid(asset: TcaAsset): bool {
    var counts: [3]u32 = [0, 0, 0];
    var phase: usize = 0;
    while phase < 4 {
        if asset.cfa[phase] > 2 {
            return false;
        }
        const color = asset.cfa[phase] as usize;
        counts[color] = counts[color] + 1;
        phase = phase + 1;
    }
    if asset.version != algorithm_version or asset.model_hash == 0
    or counts[0] != 1 or counts[1] != 2 or counts[2] != 1
    or not ((asset.cfa[0] == 1 and asset.cfa[3] == 1)
        or (asset.cfa[1] == 1 and asset.cfa[2] == 1)
    )
    or not (asset.center_x_fraction >= 0.25 and asset.center_x_fraction <= 0.75)
    or not (asset.center_y_fraction >= 0.25 and asset.center_y_fraction <= 0.75)
    or not (asset.red_k1 >= -0.25 and asset.red_k1 <= 0.25)
    or not (asset.blue_k1 >= -0.25 and asset.blue_k1 <= 0.25)
    or not (asset.maximum_change >= 0.0 and asset.maximum_change <= 1.0) {
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

fn color_at(asset: TcaAsset, x: usize, y: usize): usize {
    return asset.cfa[(y % 2) * 2 + x % 2] as usize;
}

// The point is on the matching CFA sublattice. Green remains the reference;
// the two green phases are never mixed by interpolation.
pub fn source_point(width: usize, height: usize,
    asset: TcaAsset, x: usize, y: usize
): SamplePoint {
    if not valid(asset) or width < 2 or height < 2
    or width > maximum_pixels or height > maximum_pixels / width
    or x >= width or y >= height {
        return {
            x: 0.0,
            y: 0.0,
            inside: false
        };
    }
    const color = color_at(asset, x, y);
    if color == 1 or asset.maximum_change == 0.0 {
        return {
            x: x as f64,
            y: y as f64,
            inside: true
        };
    }
    const cx = ((width - 1) as f64) * asset.center_x_fraction;
    const cy = ((height - 1) as f64) * asset.center_y_fraction;
    var far_x = cx;
    var far_y = cy;
    if (width - 1) as f64 - cx > far_x {
        far_x = (width - 1) as f64 - cx;
    }
    if (height - 1) as f64 - cy > far_y {
        far_y = (height - 1) as f64 - cy;
    }
    const dx = (x as f64) - cx;
    const dy = (y as f64) - cy;
    const radius_squared = (dx * dx + dy * dy)
    / (far_x * far_x + far_y * far_y);
    var coefficient = asset.red_k1;
    if color == 2 {
        coefficient = asset.blue_k1;
    }
    const mapped_x = cx + dx * (1.0 + coefficient * radius_squared);
    const mapped_y = cy + dy * (1.0 + coefficient * radius_squared);
    const phase_x = x % 2;
    const phase_y = y % 2;
    const last_x = (width - 1) - ((width - 1 - phase_x) % 2);
    const last_y = (height - 1) - ((height - 1 - phase_y) % 2);
    return {
        x: mapped_x,
        y: mapped_y,
        inside: mapped_x >= phase_x as f64 and mapped_x <= last_x as f64
        and mapped_y >= phase_y as f64 and mapped_y <= last_y as f64
    };
}

fn sample(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, asset: TcaAsset
): ?f32 {
    const index = y * width + x;
    const color = color_at(asset, x, y);
    if color == 1 or asset.maximum_change == 0.0
    or (color == 0 and asset.red_k1 == 0.0)
    or (color == 2 and asset.blue_k1 == 0.0) {
        return input[index];
    }
    const point = source_point(width, height, asset, x, y);
    if not point.inside {
        return asset.boundary_fill[color];
    }
    const phase_x = x % 2;
    const phase_y = y % 2;
    const lattice_x = (point.x - (phase_x as f64)) * 0.5;
    const lattice_y = (point.y - (phase_y as f64)) * 0.5;
    const x0 = phase_x + (lattice_x as usize) * 2;
    const y0 = phase_y + (lattice_y as usize) * 2;
    var x1 = x0;
    var y1 = y0;
    if x0 + 2 < width {
        x1 = x0 + 2;
    }
    if y0 + 2 < height {
        y1 = y0 + 2;
    }
    const fx = lattice_x - ((x0 - phase_x) as f64) * 0.5;
    const fy = lattice_y - ((y0 - phase_y) as f64) * 0.5;
    const upper = (1.0 - fx) * (input[y0 * width + x0] as f64)
    + fx * (input[y0 * width + x1] as f64);
    const lower = (1.0 - fx) * (input[y1 * width + x0] as f64)
    + fx * (input[y1 * width + x1] as f64);
    const candidate = (1.0 - fy) * upper + fy * lower;
    const center = input[index] as f64;
    var change = candidate - center;
    if change > asset.maximum_change {
        change = asset.maximum_change;
    }
    if change < -asset.maximum_change {
        change = -asset.maximum_change;
    }
    return math.to_f32_rounded(center + change);
}

// Immutable row-major f32 Bayer input and disjoint same-extent output.
// Same-phase interpolation needs a two-pixel source halo. Status 0 success,
// 1 asset, 2 shape/limit, 3 nonfinite input, 4 nonfinite result, 7 cancelled.
// Any nonzero status invalidates output, including partial writes.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: TcaAsset, output: []f32,
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
    if input.len() != pixels or output.len() != pixels {
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
                const index = y * width + x;
                if pass == 0 {
                    if not core.finite_sample(input[index]) {
                        return 3;
                    }
                } else {
                    const sampled = sample(input, width, height, x, y, asset);
                    if sampled is value {
                        if pass == 1 {
                            if not core.finite_sample(value) {
                                return 4;
                            }
                        } else {
                            output[index] = value;
                        }
                    } else {
                        return 4;
                    }
                }
                x = x + 1;
            }
            y = y + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
