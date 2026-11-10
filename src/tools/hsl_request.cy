import .engine.develop.hsl_grading;
import .engine.develop.tonal_color_grade;
import .engine.develop.picked_color;
import .tools.grading_request;

// Worker request v4 appends 24 little-endian signed percentages: eight hue,
// eight saturation, then eight luminance. This adapter only decodes the
// transport; the HSL component owns validation and pixel operations.
pub struct Decoded {
    pub valid: bool;
    pub edit: hsl_grading.EightBandEdit;
}

fn integer(bytes: []const u8, offset: usize): i32 {
    const raw = (bytes[offset] as u64) | ((bytes[offset + 1] as u64) << 8)
    | ((bytes[offset + 2] as u64) << 16) | ((bytes[offset + 3] as u64) << 24);
    if raw >= 2147483648 {
        return (raw as i64 - 4294967296) as i32;
    }
    return raw as i32;
}

pub fn decode(bytes: []const u8, offset: usize): Decoded {
    var edit = hsl_grading.neutral_eight_band_edit();
    if offset > bytes.len() or
    (bytes.len() - offset != 96 and bytes.len() - offset != 132 and
        bytes.len() - offset != 144 and bytes.len() - offset != 196 and
        bytes.len() - offset != 224
    ) {
        return {
            valid: false,
            edit: edit
        };
    }
    var band: usize = 0;
    while band < 8 {
        edit.hue_percent[band] = integer(bytes, offset + band * 4);
        edit.saturation_percent[band] = integer(bytes, offset + 32 + band * 4);
        edit.luminance_percent[band] = integer(bytes, offset + 64 + band * 4);
        band = band + 1;
    }
    return {
        valid: hsl_grading.valid_eight_band_edit(edit),
        edit: edit
    };
}

pub struct Graded {
    pub status: i32;
    pub pixels: [:]f64;
}

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

// The caller retains the immutable source; output is an equal-size owned
// scene-linear working frame or invalid when status is nonzero.
pub fn apply(input: []const f64, width: usize, height: usize,
    edit: hsl_grading.EightBandEdit
): Graded {
    const expanded = hsl_grading.editor_nodes(edit);
    if not expanded.valid {
        return {
            status: 5,
            pixels: []
        };
    }
    const asset: hsl_grading.GradeAsset = {
        version: hsl_grading.algorithm_version,
        nodes: expanded.nodes[..]
    };
    var pixels: [:]f64 = [: input.len()]f64;
    var index: usize = 0;
    while index < input.len() {
        pixels.push(0.0);
        index = index + 1;
    }
    const status = hsl_grading.apply_f64(input, width, height, &asset,
        pixels[..], no_cancel, 0
    );
    return {
        status: status as i32,
        pixels: pixels
    };
}

pub fn apply_with_grade(input: []const f64, width: usize, height: usize,
    hsl: hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): Graded {
    var selected: [:]f64 = [];
    var has_selection = false;
    if grade is composite {
        if composite.picked is selection {
            selected = [: input.len()]f64;
            var selected_index: usize = 0;
            while selected_index < input.len() {
                selected.push(0.0);
                selected_index = selected_index + 1;
            }
            const picked_status = picked_color.apply_f64(input, width,
                height, selection, selected[..], no_cancel, 0
            );
            if picked_status != 0 {
                return {
                    status: picked_status as i32,
                    pixels: selected
                };
            }
            has_selection = true;
        }
    }
    var mixed: Graded = {
        status: 0,
        pixels: []
    };
    if has_selection {
        mixed = apply(selected[..], width, height, hsl);
    } else {
        mixed = apply(input, width, height, hsl);
    }
    if mixed.status != 0 {
        return mixed;
    }
    if grade is edit {
        var pixels: [:]f64 = [: mixed.pixels.len()]f64;
        var index: usize = 0;
        while index < mixed.pixels.len() {
            pixels.push(0.0);
            index = index + 1;
        }
        const status = tonal_color_grade.apply_f64(mixed.pixels[..], width,
            height, edit.tonal, pixels[..], no_cancel, 0
        );
        if status != 0 {
            return {
                status: status as i32,
                pixels: pixels
            };
        }
        return {
            status: 0,
            pixels: pixels
        };
    }
    return mixed;
}
