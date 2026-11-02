import std.math;

// Linear gradient mask v1. Unitless source-image coordinates [0,1] are
// evaluated at pixel centers. Start is zero coverage, end is one coverage;
// outside the segment, projected coverage is clamped. The caller remaps the
// endpoints after geometry changes before requesting a new coverage buffer.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct GradientAsset {
    pub version: u32;
    pub start_x: f64;
    pub start_y: f64;
    pub end_x: f64;
    pub end_y: f64;
}

pub fn valid(asset: GradientAsset): bool {
    if asset.version != algorithm_version
    or not (asset.start_x >= 0.0 and asset.start_x <= 1.0
        and asset.start_y >= 0.0 and asset.start_y <= 1.0
        and asset.end_x >= 0.0 and asset.end_x <= 1.0
        and asset.end_y >= 0.0 and asset.end_y <= 1.0
    ) {
        return false;
    }
    const dx = asset.end_x - asset.start_x;
    const dy = asset.end_y - asset.start_y;
    return dx * dx + dy * dy >= 0.000000000001;
}

// Requires valid(asset) and finite continuous source-image coordinates;
// coordinates outside [0,1] are allowed and coverage is clamped to [0,1].
pub fn coverage(asset: GradientAsset, x: f64, y: f64): f64 {
    const dx = asset.end_x - asset.start_x;
    const dy = asset.end_y - asset.start_y;
    const projection = ((x - asset.start_x) * dx + (y - asset.start_y) * dy)
    / (dx * dx + dy * dy);
    if projection <= 0.0 {
        return 0.0;
    }
    if projection >= 1.0 {
        return 1.0;
    }
    return projection;
}

// Write one f32 coverage per pixel. No image samples are read or changed.
// Status: 0 success, 1 invalid asset, 2 extent/output shape,
// 3 unrepresentable rounded coverage, 7 cancelled.
// Image is limited to maximum_pixels. Poll before work and at each row. A
// cancelled buffer may be partial and must be discarded; output is caller-owned.
pub fn build(width: usize, height: usize, asset: GradientAsset, output: []f32,
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
