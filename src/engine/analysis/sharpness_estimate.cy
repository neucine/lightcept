import .engine.core.core;

// Scene-linear Rec.2020/D65 luminance sharpness statistic v1. The four-neighbor
// Laplacian at radius 1 or 2 measures spatial high-frequency energy. It is a
// focus/detail observation, not a requested sharpening strength: noise and
// scene texture also raise the score. The source image is never modified.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct Estimate {
    // 0 success, 1 shape/limit, 2 radius, 3 invalid sample, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub radius_pixels: u32;
    pub samples: usize;
    pub mean_laplacian: f64;
    pub variance: f64;
}

fn failure(status: u32): Estimate {
    return {
        status: status,
        version: algorithm_version,
        radius_pixels: 0,
        samples: 0,
        mean_laplacian: 0.0,
        variance: 0.0
    };
}

fn luminance(input: []const f32, pixel: usize): f64 {
    const index = pixel * 3;
    return 0.2627 * (input[index] as f64)
    + 0.6780 * (input[index + 1] as f64)
    + 0.0593 * (input[index + 2] as f64);
}

// Immutable interleaved f32 RGB input; source coordinates are unrotated.
// Only interior pixels with a full stencil contribute. Poll before each row
// in both passes. Failures return zero evidence, including on cancellation.
pub fn measure(input: []const f32, width: usize, height: usize, radius_pixels: u32,
    cancelled: fn (usize): bool, context: usize
): Estimate {
    if radius_pixels < 1 or radius_pixels > 2 {
        return failure(2);
    }
    const radius = radius_pixels as usize;
    if width < 2 * radius + 1 or height < 2 * radius + 1
    or width > maximum_pixels or height > maximum_pixels / width
    or input.len() != width * height * 3 {
        return failure(1);
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < width {
            const index = (row * width + column) * 3;
            if not (core.finite_sample(input[index]) and input[index] >= -0.25
                and input[index] <= 8.0
                and core.finite_sample(input[index + 1]) and input[index + 1] >= -0.25
                and input[index + 1] <= 8.0
                and core.finite_sample(input[index + 2]) and input[index + 2] >= -0.25
                and input[index + 2] <= 8.0
            ) {
                return failure(3);
            }
            column = column + 1;
        }
        row = row + 1;
    }
    var sum: f64 = 0.0;
    var sum_squared: f64 = 0.0;
    row = radius;
    while row + radius < height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = radius;
        while column + radius < width {
            const center = row * width + column;
            const laplacian = 4.0 * luminance(input, center)
            - luminance(input, center - radius)
            - luminance(input, center + radius)
            - luminance(input, center - radius * width)
            - luminance(input, center + radius * width);
            sum = sum + laplacian;
            sum_squared = sum_squared + laplacian * laplacian;
            column = column + 1;
        }
        row = row + 1;
    }
    const samples = (width - 2 * radius) * (height - 2 * radius);
    const mean = sum / (samples as f64);
    var variance = sum_squared / (samples as f64) - mean * mean;
    if variance < 0.0 {
        variance = 0.0;
    }
    return {
        status: 0,
        version: algorithm_version,
        radius_pixels: radius_pixels,
        samples: samples,
        mean_laplacian: mean,
        variance: variance
    };
}
