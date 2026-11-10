import std.math;

// Tonal color grade v1. Input is interleaved scene-linear Rec.2020/D65 RGB
// in [-128,128], allowing the preceding HSL stage's signed headroom. Output
// is the same domain, with signed headroom [-128,128].
// Wheel hues are degrees [0,359], strengths [0,100] percent, luminance
// offsets [-100,100] percent; balance is [-100,100] percent. The caller owns
// disjoint input and output buffers and discards output on any nonzero status.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 33554432;

pub struct Wheel {
    pub hue_degrees: i32;
    pub strength_percent: i32;
    pub luminance_percent: i32;
}

pub struct Edit {
    pub version: u32;
    // Shadows, midtones, highlights, global.
    pub wheels: [4]Wheel;
    pub balance_percent: i32;
}

pub fn neutral(): Edit {
    const wheel: Wheel = {
        hue_degrees: 0,
        strength_percent: 0,
        luminance_percent: 0
    };
    return {
        version: algorithm_version,
        wheels: [wheel] ** 4,
        balance_percent: 0
    };
}

pub fn valid(edit: Edit): bool {
    if edit.version != algorithm_version or edit.balance_percent < -100 or
    edit.balance_percent > 100 {
        return false;
    }
    var index: usize = 0;
    while index < 4 {
        const wheel = edit.wheels[index];
        if wheel.hue_degrees < 0 or wheel.hue_degrees >= 360 or
        wheel.strength_percent < 0 or wheel.strength_percent > 100 or
        wheel.luminance_percent < -100 or wheel.luminance_percent > 100 {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn nonneutral(edit: Edit): bool {
    if edit.balance_percent != 0 {
        return true;
    }
    var index: usize = 0;
    while index < 4 {
        if edit.wheels[index].strength_percent != 0 or
        edit.wheels[index].luminance_percent != 0 {
            return true;
        }
        index = index + 1;
    }
    return false;
}

fn clamp01(value: f64): f64 {
    if value < 0.0 {
        return 0.0;
    }
    if value > 1.0 {
        return 1.0;
    }
    return value;
}

fn smoothstep(value: f64): f64 {
    const t = clamp01(value);
    return t * t * (3.0 - 2.0 * t);
}

// A hue on the HSV perimeter, with maximum component one and minimum zero.
// It is used only to choose a tint direction. Subtracting Rec.2020 Y below
// keeps chromatic tint from changing luminance.
fn hue_rgb(degrees: i32): [3]f64 {
    const sector = degrees / 60;
    const fraction = ((degrees % 60) as f64) / 60.0;
    if sector == 0 {
        return [1.0, fraction, 0.0];
    }
    if sector == 1 {
        return [1.0 - fraction, 1.0, 0.0];
    }
    if sector == 2 {
        return [0.0, 1.0, fraction];
    }
    if sector == 3 {
        return [0.0, 1.0 - fraction, 1.0];
    }
    if sector == 4 {
        return [fraction, 0.0, 1.0];
    }
    return [1.0, 0.0, 1.0 - fraction];
}

fn grade_pixel(red: f64, green: f64, blue: f64, edit: Edit): [3]f64 {
    const luminance = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    var positive = luminance;
    if positive < 0.0 {
        positive = 0.0;
    }
    const position = positive / (positive + 0.18);
    // Positive balance gives highlights more of the tonal range.
    const shift = -(edit.balance_percent as f64) * 0.0015;
    const shadow = 1.0 - smoothstep((position - (0.30 + shift)) / 0.32);
    const highlight = smoothstep((position - (0.56 + shift)) / 0.32);
    const middle = (1.0 - shadow) * (1.0 - highlight);
    const weights: [4]f64 = [shadow, middle, highlight, 1.0];
    var tint: [3]f64 = [0.0, 0.0, 0.0];
    var luminance_ev: f64 = 0.0;
    var index: usize = 0;
    while index < 4 {
        const wheel = edit.wheels[index];
        const weight = weights[index];
        if wheel.strength_percent != 0 {
            const color = hue_rgb(wheel.hue_degrees);
            const color_y = 0.2627 * color[0] + 0.6780 * color[1] +
            0.0593 * color[2];
            const amount = weight * (wheel.strength_percent as f64) / 100.0;
            var channel: usize = 0;
            while channel < 3 {
                tint[channel] = tint[channel] + amount * (color[channel] - color_y);
                channel = channel + 1;
            }
        }
        luminance_ev = luminance_ev + weight *
        (wheel.luminance_percent as f64) / 100.0;
        index = index + 1;
    }
    const gain = math.pow_f64(2.0, luminance_ev);
    // A black pixel has no light to color. The square-root response keeps
    // grading visible in deep shadows without adding a colored black floor.
    const tint_scale = math.sqrt_f64(positive * 0.18) * 0.55;
    return [(red + tint[0] * tint_scale) * gain,
        (green + tint[1] * tint_scale) * gain,
        (blue + tint[2] * tint_scale) * gain
    ];
}

// Status: 0 success, 1 invalid edit, 2 shape/limit, 3 invalid input,
// 4 output outside signed headroom, 7 cancelled. Cancellation is polled per
// row in both validation and write passes. A failure invalidates all output.
pub fn apply_f64(input: []const f64, width: usize, height: usize,
    edit: Edit, output: []f64, cancelled: fn (usize): bool,
    context: usize
): u32 {
    if not valid(edit) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels or
    height > maximum_pixels / width {
        return 2;
    }
    const length = width * height * 3;
    if input.len() != length or output.len() != length {
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
                const offset = (row * width + column) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    if not (input[offset + channel] >= -128.0 and
                        input[offset + channel] <= 128.0
                    ) {
                        return 3;
                    }
                    channel = channel + 1;
                }
                const graded = grade_pixel(input[offset], input[offset + 1],
                    input[offset + 2], edit
                );
                channel = 0;
                while channel < 3 {
                    if not (graded[channel] >= -128.0 and
                        graded[channel] <= 128.0
                    ) {
                        return 4;
                    }
                    if pass == 1 {
                        output[offset + channel] = graded[channel];
                    }
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
