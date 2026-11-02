import .engine.core.core;
import std.math;

// Working white v1: relative per-channel gains in scene-linear Rec.2020/D65.
// Gains come from a separately versioned camera matrix and temperature/tint
// conversion. This kernel never applies sensor coefficients to working RGB.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct WorkingGains {
    pub version: u32;
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

pub fn valid(gains: WorkingGains): bool {
    return gains.version == algorithm_version
    and gains.red >= 0.125 and gains.red <= 8.0
    and gains.green >= 0.125 and gains.green <= 8.0
    and gains.blue >= 0.125 and gains.blue <= 8.0;
}

pub fn neutral(): WorkingGains {
    return {
        version: algorithm_version,
        red: 1.0,
        green: 1.0,
        blue: 1.0
    };
}

// Interleaved immutable f32 RGB in [-0.25,8], disjoint output of equal size.
// Signed values and headroom survive multiplication; output bound is [-64,64].
// Status: 0 success, 1 gain/version, 2 shape/limit, 3 input, 4 output,
// 7 cancelled. Two row-wise passes validate before writing. Failure or
// cancellation invalidates the whole output; caller never publishes it.
pub fn apply(input: []const f32, width: usize, height: usize,
    gains: WorkingGains, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(gains) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const count = width * height * 3;
    if input.len() != count or output.len() != count {
        return 2;
    }
    const factors: [3]f64 = [gains.red, gains.green, gains.blue];
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var channel: usize = row * width * 3;
            while channel < (row + 1) * width * 3 {
                const value = input[channel];
                if not core.finite_sample(value) or value < -0.25 or value > 8.0 {
                    return 3;
                }
                const factor = factors[channel % 3];
                const result = (value as f64) * factor;
                if not (result >= -64.0 and result <= 64.0) {
                    return 4;
                }
                if pass == 1 {
                    if factor == 1.0 {
                        output[channel] = value;
                    } else {
                        const rounded = math.to_f32_rounded(result);
                        if rounded is converted {
                            output[channel] = converted;
                        } else {
                            return 4;
                        }
                    }
                }
                channel = channel + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
