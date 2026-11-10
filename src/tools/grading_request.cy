import .engine.develop.tonal_color_grade;
import .engine.develop.picked_color;

pub struct GradingRecipe {
    pub tonal: tonal_color_grade.Edit;
    pub picked: ?picked_color.SelectionEdit;
}

pub struct Decoded {
    pub valid: bool;
    pub edit: GradingRecipe;
}

fn integer(bytes: []const u8, offset: usize): i32 {
    const raw = (bytes[offset] as u64) | ((bytes[offset + 1] as u64) << 8)
    | ((bytes[offset + 2] as u64) << 16) | ((bytes[offset + 3] as u64) << 24);
    if raw >= 2147483648 {
        return (raw as i64 - 4294967296) as i32;
    }
    return raw as i32;
}

// Worker request v7 appends four hue/strength/luminance wheels and balance.
pub fn decode(bytes: []const u8, offset: usize): Decoded {
    var edit = tonal_color_grade.neutral();
    if offset > bytes.len() or
    (bytes.len() - offset != 52 and bytes.len() - offset != 80) {
        return {
            valid: false,
            edit: {
                tonal: edit,
                picked: none
            }
        };
    }
    var wheel: usize = 0;
    while wheel < 4 {
        const field = offset + wheel * 12;
        edit.wheels[wheel] = {
            hue_degrees: integer(bytes, field),
            strength_percent: integer(bytes, field + 4),
            luminance_percent: integer(bytes, field + 8)
        };
        wheel = wheel + 1;
    }
    edit.balance_percent = integer(bytes, offset + 48);
    var picked: ?picked_color.SelectionEdit = none;
    if bytes.len() - offset == 80 {
        var width = integer(bytes, offset + 56);
        var softness = integer(bytes, offset + 60);
        if width == 0 {
            width = 20;
        }
        if softness == 0 {
            softness = 50;
        }
        const selection: picked_color.SelectionEdit = {
            version: picked_color.algorithm_version,
            center_degrees: integer(bytes, offset + 52),
            half_width_degrees: width,
            softness_percent: softness,
            hue_shift_percent: integer(bytes, offset + 64),
            saturation_percent: integer(bytes, offset + 68),
            brightness_percent: integer(bytes, offset + 72),
            enabled: integer(bytes, offset + 76) == 1
        };
        if integer(bytes, offset + 76) < 0 or
        integer(bytes, offset + 76) > 1 or not picked_color.valid(selection) {
            return {
                valid: false,
                edit: {
                    tonal: edit,
                    picked: none
                }
            };
        }
        picked = selection;
    }
    return {
        valid: tonal_color_grade.valid(edit),
        edit: {
            tonal: edit,
            picked: picked
        }
    };
}

fn no_cancel(context: usize): bool {
    return false;
}

pub struct Graded {
    pub status: i32;
    pub pixels: [:]f64;
}

pub fn apply(input: []const f64, width: usize, height: usize,
    edit: tonal_color_grade.Edit
): Graded {
    var pixels: [:]f64 = [: input.len()]f64;
    var index: usize = 0;
    while index < input.len() {
        pixels.push(0.0);
        index = index + 1;
    }
    const status = tonal_color_grade.apply_f64(input, width, height, edit,
        pixels[..], no_cancel, 0
    );
    return {
        status: status as i32,
        pixels: pixels
    };
}
