import .engine.core.core;
import std.math;

// Described mask raster v1. A caller supplies immutable coverage produced
// from a semantic description and explicit destination-to-source coordinates.
// This component resamples coverage; it does not run a model or alter pixels.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct MaskAsset {
    pub version: u32;
    // Nonzero identities bind the caller's source image, description, and
    // producer revision. They are opaque IDs, not cryptographic digests.
    pub source_image_id: u64;
    pub description_id: u64;
    pub producer_version: u32;
    pub width: usize;
    pub height: usize;
    // Top-left row-major source coverage, one f32 in [0,1] per pixel.
    pub coverage: []const f32;
}

fn valid_header(asset: &const MaskAsset): bool {
    if asset.version != algorithm_version or asset.source_image_id == 0
    or asset.description_id == 0 or asset.producer_version == 0
    or asset.width == 0 or asset.height == 0
    or asset.width > maximum_pixels
    or asset.height > maximum_pixels / asset.width
    or asset.coverage.len() != asset.width * asset.height {
        return false;
    }
    return true;
}

pub fn valid(asset: &const MaskAsset): bool {
    if not valid_header(asset) {
        return false;
    }
    var index: usize = 0;
    while index < asset.coverage.len() {
        const value = asset.coverage[index];
        if not core.finite_sample(value) or value < 0.0 or value > 1.0 {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn source_sample(asset: &const MaskAsset, column: usize, row: usize): f64 {
    return asset.coverage[row * asset.width + column] as f64;
}

// x,y are normalized source coordinates, top-left origin. Coordinates
// outside [0,1] return zero. Inside, pixel centers are (i+0.5)/extent;
// source-edge samples clamp to the nearest center before bilinear sampling.
fn sample(asset: &const MaskAsset, x: f64, y: f64): f64 {
    if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0 {
        return 0.0;
    }
    var sx = x * asset.width as f64 - 0.5;
    var sy = y * asset.height as f64 - 0.5;
    if sx < 0.0 {
        sx = 0.0;
    }
    if sy < 0.0 {
        sy = 0.0;
    }
    const last_x = asset.width - 1;
    const last_y = asset.height - 1;
    if sx > last_x as f64 {
        sx = last_x as f64;
    }
    if sy > last_y as f64 {
        sy = last_y as f64;
    }
    const x0 = sx as usize;
    const y0 = sy as usize;
    var x1 = x0 + 1;
    var y1 = y0 + 1;
    if x1 > last_x {
        x1 = last_x;
    }
    if y1 > last_y {
        y1 = last_y;
    }
    const fx = sx - x0 as f64;
    const fy = sy - y0 as f64;
    const top = source_sample(asset, x0, y0) * (1.0 - fx)
    + source_sample(asset, x1, y0) * fx;
    const bottom = source_sample(asset, x0, y1) * (1.0 - fx)
    + source_sample(asset, x1, y1) * fx;
    return top * (1.0 - fy) + bottom * fy;
}

// map_x,map_y give normalized source coordinates per destination pixel and
// may extend to [-1,2] for pixels outside the source after a geometry warp.
// Output is caller-owned f32 coverage, one per destination pixel. Two passes
// validate map and projected coverage before writes; cancellation every row.
// Status: 0 success, 1 asset, 2 extent/shape/limit, 3 map, 4 result,
// 7 cancelled. Any nonzero status invalidates the entire output.
pub fn build(asset: &const MaskAsset, map_x: []const f32, map_y: []const f32,
    width: usize, height: usize, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid_header(asset) {
        return 1;
    }
    var source_row: usize = 0;
    while source_row < asset.height {
        if cancelled(context) {
            return 7;
        }
        var source_column: usize = 0;
        while source_column < asset.width {
            const value = asset.coverage[source_row * asset.width + source_column];
            if not core.finite_sample(value) or value < 0.0 or value > 1.0 {
                return 1;
            }
            source_column = source_column + 1;
        }
        source_row = source_row + 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if map_x.len() != pixels or map_y.len() != pixels
    or output.len() != pixels {
        return 2;
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var column: usize = 0;
            while column < width {
                const index = row * width + column;
                const x = map_x[index];
                const y = map_y[index];
                if not (core.finite_sample(x) and core.finite_sample(y)
                    and x >= -1.0 and x <= 2.0
                    and y >= -1.0 and y <= 2.0
                ) {
                    return 3;
                }
                const value = sample(asset, x as f64, y as f64);
                if not (value >= 0.0 and value <= 1.0) {
                    return 4;
                }
                if pass == 1 {
                    const rounded = math.to_f32_rounded(value);
                    if rounded is sample {
                        output[index] = sample;
                    } else {
                        return 4;
                    }
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
