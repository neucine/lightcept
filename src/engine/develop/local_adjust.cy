import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 local composite v1. An independently executed
// eligible stage supplies edited RGB; this component owns only compositing.
// Coverage is unitless [0,1]. Amount is an integer percent in [0,200].
// Values above 100 extrapolate the stage difference; no gamut clip occurs.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub fn mix(base: f64, edited: f64, coverage: f64, amount_percent: u32): f64 {
    if coverage == 0.0 or amount_percent == 0 {
        return base;
    }
    return base + coverage * (amount_percent as f64 / 100.0) * (edited - base);
}

// Disjoint caller-owned buffers: base and edited are immutable interleaved
// f32 RGB, mask has one f32 coverage per pixel, output is interleaved f32 RGB.
// Status: 0 success, 1 amount, 2 shape/limit, 3 nonfinite input or bad mask,
// 4 output outside finite f32 range, 7 cancelled. The validation pass checks
// all results before writing. Poll at every row in both passes; discard a
// partial output on any nonzero status. The caller proves that all four buffers
// have the same stage geometry and that the edited stage admits local blending.
pub fn composite(base: []const f32, edited: []const f32, mask: []const f32,
    width: usize, height: usize, amount_percent: u32, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if amount_percent > 200 {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if base.len() != pixels * 3 or edited.len() != pixels * 3
    or mask.len() != pixels or output.len() != pixels * 3 {
        return 2;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const pixel = row * width + column;
            const weight = mask[pixel];
            if not core.finite_sample(weight) or weight < 0.0 or weight > 1.0 {
                return 3;
            }
            var channel: usize = 0;
            while channel < 3 {
                const index = pixel * 3 + channel;
                if not core.finite_sample(base[index]) or not core.finite_sample(edited[index]) {
                    return 3;
                }
                const result = mix(base[index] as f64, edited[index] as f64,
                    weight as f64, amount_percent
                );
                const rounded = math.to_f32_rounded(result);
                if rounded is sample {
                    if not core.finite_sample(sample) {
                        return 4;
                    }
                } else {
                    return 4;
                }
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    row = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const pixel = row * width + column;
            var channel: usize = 0;
            while channel < 3 {
                const index = pixel * 3 + channel;
                const rounded = math.to_f32_rounded(mix(base[index] as f64,
                    edited[index] as f64, mask[pixel] as f64, amount_percent
                ));
                if rounded is sample {
                    output[index] = sample;
                } else {
                    return 4;
                }
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
