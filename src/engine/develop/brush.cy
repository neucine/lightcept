import std.math;

// Brush mask v1. Each stroke is a polyline of source pixel coordinates. The
// stroke's outer radius is in pixels; its inner fraction has full coverage.
// Connected points form round-capped capsules. Strokes combine by maximum.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
pub const maximum_points: usize = 1024;
pub const maximum_strokes: usize = 64;
pub const maximum_work: usize = 67108864;

pub struct Point {
    pub x: f64;
    pub y: f64;
}

pub struct Stroke {
    pub first: usize;
    pub count: usize;
    pub radius_pixels: f64;
    pub inner_fraction: f64;
}

pub struct BrushAsset {
    pub version: u32;
    pub points: [:]Point;
    pub strokes: [:]Stroke;
}

pub fn valid(asset: &const BrushAsset, width: usize, height: usize): bool {
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width
    or asset.version != algorithm_version or asset.points.len() == 0
    or asset.points.len() > maximum_points or asset.strokes.len() == 0
    or asset.strokes.len() > maximum_strokes {
        return false;
    }
    var index: usize = 0;
    while index < asset.points.len() {
        const point = asset.points[index];
        if not (point.x >= 0.0 and point.x <= width as f64
            and point.y >= 0.0 and point.y <= height as f64
        ) {
            return false;
        }
        index = index + 1;
    }
    index = 0;
    while index < asset.strokes.len() {
        const stroke = asset.strokes[index];
        if stroke.count == 0 or stroke.first >= asset.points.len()
        or stroke.count > asset.points.len() - stroke.first
        or not (stroke.radius_pixels >= 0.5 and stroke.radius_pixels <= 512.0)
        or not (stroke.inner_fraction >= 0.0 and stroke.inner_fraction < 1.0) {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn segment_distance_squared(x: f64, y: f64, first: Point, last: Point): f64 {
    const dx = last.x - first.x;
    const dy = last.y - first.y;
    const length_squared = dx * dx + dy * dy;
    var t: f64 = 0.0;
    if length_squared > 0.0 {
        t = ((x - first.x) * dx + (y - first.y) * dy) / length_squared;
        if t < 0.0 {
            t = 0.0;
        }
        if t > 1.0 {
            t = 1.0;
        }
    }
    const offset_x = x - (first.x + t * dx);
    const offset_y = y - (first.y + t * dy);
    return offset_x * offset_x + offset_y * offset_y;
}

fn stroke_coverage(asset: &const BrushAsset, stroke: Stroke, x: f64, y: f64): f64 {
    var distance_squared = segment_distance_squared(x, y,
        asset.points[stroke.first], asset.points[stroke.first]
    );
    var index: usize = 1;
    while index < stroke.count {
        const candidate = segment_distance_squared(x, y,
            asset.points[stroke.first + index - 1], asset.points[stroke.first + index]
        );
        if candidate < distance_squared {
            distance_squared = candidate;
        }
        index = index + 1;
    }
    const distance = math.sqrt_f64(distance_squared as f64) as f64;
    const inner = stroke.radius_pixels * stroke.inner_fraction;
    if distance <= inner {
        return 1.0;
    }
    if distance >= stroke.radius_pixels {
        return 0.0;
    }
    const t = (stroke.radius_pixels - distance) / (stroke.radius_pixels - inner);
    return t * t * (3.0 - 2.0 * t);
}

// Requires an asset accepted by valid() for its raster and finite coordinates.
pub fn coverage(asset: &const BrushAsset, x: f64, y: f64): f64 {
    var value: f64 = 0.0;
    var index: usize = 0;
    while index < asset.strokes.len() {
        const candidate = stroke_coverage(asset, asset.strokes[index], x, y);
        if candidate > value {
            value = candidate;
        }
        index = index + 1;
    }
    return value;
}

// One caller-owned f32 mask sample per pixel. Shape/status: 0 success, 1
// invalid asset, 2 shape/limit/work, 3 unrepresentable rounded coverage,
// 7 cancelled. Pixel centers are in source
// coordinates. Poll at least every 64 pixels and on row starts. A cancelled
// buffer may be partial and is invalid. The caller remaps strokes after warps.
pub fn build(width: usize, height: usize, asset: &const BrushAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if output.len() != pixels {
        return 2;
    }
    if not valid(asset, width, height) {
        return 1;
    }
    const allowed_units = maximum_work / pixels;
    var work_units: usize = 0;
    var stroke_index: usize = 0;
    while stroke_index < asset.strokes.len() {
        const count = asset.strokes[stroke_index].count;
        if count > allowed_units - work_units {
            return 2;
        }
        work_units = work_units + count;
        stroke_index = stroke_index + 1;
    }
    var pixel: usize = 0;
    while pixel < pixels {
        if pixel % 64 == 0 and cancelled(context) {
            return 7;
        }
        const x = (pixel % width) as f64 + 0.5;
        const y = (pixel / width) as f64 + 0.5;
        const rounded = math.to_f32_rounded(coverage(asset, x, y));
        if rounded is value {
            output[pixel] = value;
        } else {
            return 3;
        }
        pixel = pixel + 1;
    }
    return 0;
}
