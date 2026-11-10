import .engine.develop.hsl_grading;
import .engine.develop.hue;
import .engine.develop.linear_chroma;
import .engine.color.output_color;

// Picked color v1, scene-linear Rec.2020/D65 RGB in [-128,128]. Hue and
// range are degrees; shifts and softness are percentages. The source frame
// is immutable. Output has the same signed domain and is invalid on failure.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 33554432;

pub struct SelectionEdit {
    pub version: u32;
    pub enabled: bool;
    pub center_degrees: i32;
    pub half_width_degrees: i32;
    pub softness_percent: i32;
    pub hue_shift_percent: i32;
    pub saturation_percent: i32;
    pub brightness_percent: i32;
}

pub fn neutral(): SelectionEdit {
    return {
        version: algorithm_version,
        enabled: false,
        center_degrees: 0,
        half_width_degrees: 0,
        softness_percent: 0,
        hue_shift_percent: 0,
        saturation_percent: 0,
        brightness_percent: 0
    };
}

pub fn valid(edit: SelectionEdit): bool {
    if edit.version != algorithm_version or edit.center_degrees < 0 or
    edit.center_degrees >= 360 or edit.half_width_degrees < 0 or
    edit.half_width_degrees > 90 or edit.softness_percent < 0 or
    edit.softness_percent > 100 or edit.hue_shift_percent < -100 or
    edit.hue_shift_percent > 100 or edit.saturation_percent < -100 or
    edit.saturation_percent > 100 or edit.brightness_percent < -100 or
    edit.brightness_percent > 100 {
        return false;
    }
    return not edit.enabled or edit.half_width_degrees >= 2;
}

fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}

fn smoothstep(value: f64): f64 {
    if value <= 0.0 {
        return 0.0;
    }
    if value >= 1.0 {
        return 1.0;
    }
    return value * value * (3.0 - 2.0 * value);
}

pub fn weight(red: f64, green: f64, blue: f64, edit: SelectionEdit): f64 {
    if not edit.enabled {
        return 0.0;
    }
    const axes = hsl_grading.coordinates(red, green, blue);
    const chroma_weight = smoothstep((axes[1] - 0.02) / 0.08);
    var distance = absolute(axes[0] - (edit.center_degrees as f64));
    if distance > 180.0 {
        distance = 360.0 - distance;
    }
    const outer = edit.half_width_degrees as f64;
    const core = outer * (1.0 - (edit.softness_percent as f64) / 100.0);
    if distance <= core {
        return chroma_weight;
    }
    if distance >= outer {
        return 0.0;
    }
    if outer == core {
        return 0.0;
    }
    return chroma_weight * (1.0 - smoothstep((distance - core) / (outer - core)));
}

// Returns -1 for a neutral or invalid sample, otherwise a hue in [0,359].
pub fn sample_hue(red: f64, green: f64, blue: f64): i32 {
    if not (red >= -128.0 and red <= 128.0 and green >= -128.0 and
        green <= 128.0 and blue >= -128.0 and blue <= 128.0
    ) {
        return -1;
    }
    const axes = hsl_grading.coordinates(red, green, blue);
    if axes[1] < 0.02 {
        return -1;
    }
    return ((axes[0] + 0.5) as i32) % 360;
}

fn change(red: f64, green: f64, blue: f64, edit: SelectionEdit): [3]f64 {
    const influence = weight(red, green, blue, edit);
    if influence == 0.0 or (edit.hue_shift_percent == 0 and
        edit.saturation_percent == 0 and edit.brightness_percent == 0
    ) {
        return [red, green, blue];
    }
    const rotated = hue.rotate(red, green, blue, {
        version: hue.algorithm_version,
        angle_degrees: (edit.hue_shift_percent as f64) * 0.45
    });
    const chroma = linear_chroma.apply_native(rotated[0], rotated[1],
        rotated[2], 1.0 + (edit.saturation_percent as f64) / 100.0
    );
    const gain = output_color.exposure_gain_native(
        (edit.brightness_percent as f64) / 100.0
    );
    return [red + influence * (chroma.red * gain - red),
        green + influence * (chroma.green * gain - green),
        blue + influence * (chroma.blue * gain - blue)
    ];
}

// Status: 0 success, 1 invalid edit, 2 shape/limit, 3 input,
// 4 output outside signed headroom, 7 cancelled. Poll per row in both passes.
pub fn apply_f64(input: []const f64, width: usize, height: usize,
    edit: SelectionEdit, output: []f64, cancelled: fn (usize): bool,
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
                const result = change(input[offset], input[offset + 1],
                    input[offset + 2], edit
                );
                channel = 0;
                while channel < 3 {
                    if not (result[channel] >= -128.0 and
                        result[channel] <= 128.0
                    ) {
                        return 4;
                    }
                    if pass == 1 {
                        output[offset + channel] = result[channel];
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

// An RGBA8 display mask for the same source selection. Unselected pixels get
// a dark overlay; selected pixels remain visible. The caller supplies a
// bounded preview extent and four bytes per output pixel.
pub fn mask_rgba(input: *const f64, input_len: usize, source_width: usize,
    source_height: usize, edit: SelectionEdit, output: *u8,
    output_len: usize, mask_width: usize, mask_height: usize
): i32 {
    if not valid(edit) or source_width == 0 or source_height == 0 or
    source_width > maximum_pixels or source_height > maximum_pixels / source_width or
    input_len != source_width * source_height * 3 or mask_width == 0 or
    mask_height == 0 or mask_width > 512 or mask_height > 512 or
    output_len != mask_width * mask_height * 4 {
        return 1;
    }
    var y: usize = 0;
    while y < mask_height {
        const sy = y * source_height / mask_height;
        var x: usize = 0;
        while x < mask_width {
            const sx = x * source_width / mask_width;
            const offset = (sy * source_width + sx) * 3;
            var red: f64 = 0.0;
            var green: f64 = 0.0;
            var blue: f64 = 0.0;
            unchecked {
                red = *(((input as! usize) + offset * 8) as! *const f64);
                green = *(((input as! usize) + (offset + 1) * 8) as! *const f64);
                blue = *(((input as! usize) + (offset + 2) * 8) as! *const f64);
            }
            if not (red >= -128.0 and red <= 128.0 and green >= -128.0 and
                green <= 128.0 and blue >= -128.0 and blue <= 128.0
            ) {
                return 2;
            }
            const influence = weight(red, green, blue, edit);
            const alpha = (185.0 * (1.0 - influence) + 0.5) as u8;
            const output_offset = (y * mask_width + x) * 4;
            unchecked {
                *(((output as! usize) + output_offset) as! *u8) = 0;
                *(((output as! usize) + output_offset + 1) as! *u8) = 0;
                *(((output as! usize) + output_offset + 2) as! *u8) = 0;
                *(((output as! usize) + output_offset + 3) as! *u8) = alpha;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    return 0;
}
