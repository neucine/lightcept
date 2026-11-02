import std.math;

// Ellipse geometry mask v1. Unitless source-image coordinates [0,1] are
// evaluated at pixel centers. Outer radii are fractions of image width and
// height. An inner fraction defines the full-coverage ellipse; the annulus
// to the outer ellipse receives a cubic feather. No image pixels are read.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct EllipseAsset {
    pub version: u32;
    pub center_x: f64;
    pub center_y: f64;
    pub radius_x: f64;
    pub radius_y: f64;
    pub inner_fraction: f64;
}

pub fn valid(asset: EllipseAsset): bool {
    return asset.version == algorithm_version
    and asset.center_x >= 0.0 and asset.center_x <= 1.0
    and asset.center_y >= 0.0 and asset.center_y <= 1.0
    and asset.radius_x >= 0.000001 and asset.radius_x <= 1.0
    and asset.radius_y >= 0.000001 and asset.radius_y <= 1.0
    and asset.inner_fraction >= 0.0 and asset.inner_fraction < 1.0;
}

// Requires valid(asset) and finite continuous source-image coordinates;
// coordinates outside [0,1] are allowed and coverage remains in [0,1].
pub fn coverage(asset: EllipseAsset, x: f64, y: f64): f64 {
    const dx = (x - asset.center_x) / asset.radius_x;
    const dy = (y - asset.center_y) / asset.radius_y;
    const radius = math.sqrt_f64((dx * dx + dy * dy) as f64) as f64;
    if radius <= asset.inner_fraction {
        return 1.0;
    }
    if radius >= 1.0 {
        return 0.0;
    }
    const t = (1.0 - radius) / (1.0 - asset.inner_fraction);
    return t * t * (3.0 - 2.0 * t);
}

// Caller-owned f32 coverage output, one sample per pixel. Status: 0 success,
// 1 invalid asset, 2 shape/limit, 3 unrepresentable result, 7 cancelled. Poll before each row. A
// cancelled output may be partial and is invalid. The caller tracks the
// source geometry identity and remaps the asset after any coordinate warp.
pub fn build(width: usize, height: usize, asset: EllipseAsset, output: []f32,
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
    if output.len() != pixels {
        return 2;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const x = (column as f64 + 0.5) / (width as f64);
            const y = (row as f64 + 0.5) / (height as f64);
            const rounded = math.to_f32_rounded(coverage(asset, x, y));
            if rounded is value {
                output[row * width + column] = value;
            } else {
                return 3;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
