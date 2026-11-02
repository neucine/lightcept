import .engine.core.core;
import std.math;

// Diagnostic Bayer residual energy v1. Input is a black-subtracted,
// white-normalized camera-linear f32 mosaic in unrotated sensor coordinates.
// The 2x2 CFA entries are 0 red, 1 green, 2 blue. Horizontal samples two
// columns apart share CFA color. The second difference is divided by six,
// the variance factor for independent equal-variance sample noise. Scene
// texture also contributes, so this is not a calibrated sensor noise profile.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct Estimate {
    // 0 success, 1 extent/shape, 2 invalid CFA, 3 nonfinite/out-of-domain
    // sample, 4 insufficient unclipped samples, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub red_count: usize;
    pub green_count: usize;
    pub blue_count: usize;
    pub red_variance: f64;
    pub green_variance: f64;
    pub blue_variance: f64;
    pub red_sigma: f64;
    pub green_sigma: f64;
    pub blue_sigma: f64;
}

fn failure(status: u32): Estimate {
    return {
        status: status,
        version: algorithm_version,
        red_count: 0,
        green_count: 0,
        blue_count: 0,
        red_variance: 0.0,
        green_variance: 0.0,
        blue_variance: 0.0,
        red_sigma: 0.0,
        green_sigma: 0.0,
        blue_sigma: 0.0
    };
}

pub fn valid_cfa(cfa: [4]u32): bool {
    var red: u32 = 0;
    var green: u32 = 0;
    var blue: u32 = 0;
    var index: usize = 0;
    while index < 4 {
        if cfa[index] == 0 {
            red = red + 1;
        } else if cfa[index] == 1 {
            green = green + 1;
        } else if cfa[index] == 2 {
            blue = blue + 1;
        } else {
            return false;
        }
        index = index + 1;
    }
    return red == 1 and green == 2 and blue == 1
    and ((cfa[0] == 1 and cfa[3] == 1)
        or (cfa[1] == 1 and cfa[2] == 1)
    );
}

// The whole image is read-only and limited to maximum_pixels. Candidates
// containing any sample >= 0.98 or < 0 are excluded from variance sums.
// Poll before each row in both passes. A nonzero status returns zero evidence.
pub fn measure(input: []const f32, width: usize, height: usize, cfa: [4]u32,
    cancelled: fn (usize): bool, context: usize
): Estimate {
    if width < 8 or height < 4 or width > maximum_pixels
    or height > maximum_pixels / width or input.len() != width * height {
        return failure(1);
    }
    if not valid_cfa(cfa) {
        return failure(2);
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < width {
            const sample = input[row * width + column];
            if not core.finite_sample(sample) or sample < -0.25 or sample > 8.0 {
                return failure(3);
            }
            column = column + 1;
        }
        row = row + 1;
    }
    var counts: [3]usize = [0, 0, 0];
    var sums: [3]f64 = [0.0, 0.0, 0.0];
    row = 0;
    while row < height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 2;
        while column + 2 < width {
            const index = row * width + column;
            const left = input[index - 2] as f64;
            const center = input[index] as f64;
            const right = input[index + 2] as f64;
            if left >= 0.0 and center >= 0.0 and right >= 0.0
            and left < 0.98 and center < 0.98 and right < 0.98 {
                const color = cfa[(row % 2) * 2 + column % 2] as usize;
                const residual = left - 2.0 * center + right;
                counts[color] = counts[color] + 1;
                sums[color] = sums[color] + residual * residual;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    if counts[0] < 4 or counts[1] < 4 or counts[2] < 4 {
        return failure(4);
    }
    const red_variance = sums[0] / (6.0 * counts[0] as f64);
    const green_variance = sums[1] / (6.0 * counts[1] as f64);
    const blue_variance = sums[2] / (6.0 * counts[2] as f64);
    return {
        status: 0,
        version: algorithm_version,
        red_count: counts[0],
        green_count: counts[1],
        blue_count: counts[2],
        red_variance: red_variance,
        green_variance: green_variance,
        blue_variance: blue_variance,
        red_sigma: math.sqrt_f64(red_variance as f64) as f64,
        green_sigma: math.sqrt_f64(green_variance as f64) as f64,
        blue_sigma: math.sqrt_f64(blue_variance as f64) as f64
    };
}
