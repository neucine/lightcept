import lightcept_core.engine.develop.photo_geometry;
import lightcept_core.engine.develop.orthogonal_transform;

// Eight signed percentages per word, stored as unsigned bytes biased by 100.
// This keeps each fixed history snapshot small while preserving exact values.
const neutral_hsl_word: u64 = 0x6464646464646464;
pub struct HslValues {
    pub version: u32;
    pub words: [3]u64;
}

pub fn neutral_hsl(): HslValues {
    return {
        version: 1,
        words: [neutral_hsl_word] ** 3
    };
}

pub fn nonneutral_hsl(values: HslValues): bool {
    return values.words[0] != neutral_hsl_word or
    values.words[1] != neutral_hsl_word or
    values.words[2] != neutral_hsl_word;
}

// Kind 0 hue, 1 saturation, 2 luminance; band 0..7. Invalid coordinates
// return 0 only to avoid an unchecked array access; callers validate first.
pub fn hsl_percent(values: HslValues, kind: usize, band: usize): i32 {
    if kind >= 3 or band >= 8 {
        return 0;
    }
    return (((values.words[kind] >> ((band * 8) as u32)) & 255) as i32) - 100;
}

pub fn with_hsl_percent(values: HslValues, kind: usize, band: usize,
    percent: i32
): ?HslValues {
    if kind >= 3 or band >= 8 or percent < -100 or percent > 100 or not valid_hsl(values) {
        return none;
    }
    var updated = values;
    const shift = (band * 8) as u32;
    const mask = (255 as u64) << shift;
    updated.words[kind] = (updated.words[kind] & ~mask)
    | (((percent + 100) as u64) << shift);
    return updated;
}

pub fn valid_hsl(values: HslValues): bool {
    if values.version != 1 {
        return false;
    }
    var band: usize = 0;
    while band < 8 {
        var kind: usize = 0;
        while kind < 3 {
            if ((values.words[kind] >> ((band * 8) as u32)) & 255) > 200 {
                return false;
            }
            kind = kind + 1;
        }
        band = band + 1;
    }
    return true;
}

// Encoded sRGB/D65 output positions in thousandths. Channel order is red,
// green, blue, luma; fixed input positions are 0.25, 0.5, and 0.75.
pub fn neutral_curve(): [12]i32 {
    return [250, 500, 750, 250, 500, 750, 250, 500, 750, 250, 500, 750];
}

pub fn nonneutral_curve(values: [12]i32): bool {
    return values != neutral_curve();
}

pub fn valid_curve(values: [12]i32): bool {
    var channel: usize = 0;
    while channel < 4 {
        const offset = channel * 3;
        if values[offset] < 0 or values[offset] > values[offset + 1] or
        values[offset + 1] > values[offset + 2] or values[offset + 2] > 1000 {
            return false;
        }
        channel = channel + 1;
    }
    return true;
}

pub fn with_curve_point(values: [12]i32, channel: usize, point: usize,
    output: i32
): ?[12]i32 {
    if channel >= 4 or point >= 3 or output < 0 or output > 1000 or
    not valid_curve(values) {
        return none;
    }
    var changed = values;
    changed[channel * 3 + point] = output;
    if not valid_curve(changed) {
        return none;
    }
    return changed;
}

pub fn valid_grade(values: [20]i32): bool {
    var wheel: usize = 0;
    while wheel < 4 {
        const offset = wheel * 3;
        if values[offset] < 0 or values[offset] >= 360 or
        values[offset + 1] < 0 or values[offset + 1] > 100 or
        values[offset + 2] < -100 or values[offset + 2] > 100 {
            return false;
        }
        wheel = wheel + 1;
    }
    return values[12] >= -100 and values[12] <= 100 and
    values[13] >= 0 and values[13] < 360 and
    values[14] >= 0 and values[14] <= 90 and
    values[15] >= 0 and values[15] <= 100 and
    values[16] >= -100 and values[16] <= 100 and
    values[17] >= -100 and values[17] <= 100 and
    values[18] >= -100 and values[18] <= 100 and
    values[19] >= 0 and values[19] <= 1;
}

pub fn nonneutral_grade(values: [20]i32): bool {
    var wheel: usize = 0;
    while wheel < 4 {
        const offset = wheel * 3;
        if values[offset] != 0 or values[offset + 1] != 0 or
        values[offset + 2] != 0 {
            return true;
        }
        wheel = wheel + 1;
    }
    return values[12] != 0;
}

pub fn nonneutral_picked(values: [20]i32): bool {
    var index: usize = 13;
    while index < 20 {
        if values[index] != 0 {
            return true;
        }
        index = index + 1;
    }
    return false;
}

// Bounded, per-document snapshots of develop controls and source geometry.
pub struct Values {
    pub exposure_tenths: i32;
    pub contrast_percent: i32;
    pub shadows_percent: i32;
    pub highlights_percent: i32;
    pub blacks_percent: i32;
    pub whites_percent: i32;
    pub warmth_percent: i32;
    pub tint_percent: i32;
    pub vibrance_percent: i32;
    pub saturation_percent: i32;
    pub clarity_percent: i32;
    pub texture_percent: i32;
    // Zero extent means the full upright source canvas. Geometry is stored
    // with each develop snapshot so undo and redo select one complete recipe.
    pub crop_left: i32;
    pub crop_top: i32;
    pub crop_width: i32;
    pub crop_height: i32;
    pub straighten_millidegrees: i32;
    // TIFF orientation code for the user transform; 1 is identity.
    pub transform_code: i32;
    pub hsl: HslValues;
    pub curve: [12]i32;
    // Four wheels of hue, strength, luminance, followed by tonal balance.
    // Fields 13..19 describe the picked color selection and adjustments.
    pub grade: [20]i32;
}

pub struct History {
    pub entries: [32]Values;
    pub length: usize;
    pub cursor: usize;
}

pub fn neutral(): Values {
    return {
        exposure_tenths: 0,
        contrast_percent: 0,
        shadows_percent: 0,
        highlights_percent: 0,
        blacks_percent: 0,
        whites_percent: 0,
        warmth_percent: 0,
        tint_percent: 0,
        vibrance_percent: 0,
        saturation_percent: 0,
        clarity_percent: 0,
        texture_percent: 0,
        crop_left: 0,
        crop_top: 0,
        crop_width: 0,
        crop_height: 0,
        straighten_millidegrees: 0,
        transform_code: 1,
        hsl: neutral_hsl(),
        curve: neutral_curve(),
        grade: [0] ** 20
    };
}

// Convert the persisted integer angle to the headless scene-linear geometry
// recipe. A zero rectangle selects the full upright source canvas.
pub fn geometry(values: Values, source_width: usize,
    source_height: usize
): ?photo_geometry.Recipe {
    if source_width == 0 or source_height == 0 {
        return none;
    }
    var recipe = photo_geometry.neutral(source_width, source_height);
    if values.crop_width != 0 or values.crop_height != 0 {
        if values.crop_left < 0 or values.crop_top < 0 or
        values.crop_width <= 0 or values.crop_height <= 0 {
            return none;
        }
        var selected = recipe.crop;
        selected.left = values.crop_left as usize;
        selected.top = values.crop_top as usize;
        selected.width = values.crop_width as usize;
        selected.height = values.crop_height as usize;
        recipe.crop = selected;
    }
    var rotation = recipe.straighten;
    rotation.angle_radians =
    (values.straighten_millidegrees as f64) * 3.141592653589793 / 180000.0;
    recipe.straighten = rotation;
    if not photo_geometry.valid(recipe, source_width, source_height) {
        return none;
    }
    return recipe;
}

pub fn geometry_v2(values: Values, source_width: usize,
    source_height: usize
): ?photo_geometry.RecipeV2 {
    if source_width == 0 or source_height == 0 or
    values.transform_code < 1 or values.transform_code > 8 {
        return none;
    }
    const shape = orthogonal_transform.extent({
        version: 1,
        code: values.transform_code as u32
    }, source_width, source_height);
    if shape.status != 0 {
        return none;
    }
    var recipe: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: photo_geometry.neutral(source_width, source_height).straighten,
        transform: {
            version: 1,
            code: values.transform_code as u32
        },
        crop: photo_geometry.neutral(shape.width, shape.height).crop
    };
    recipe.straighten.angle_radians =
    (values.straighten_millidegrees as f64) * 3.141592653589793 / 180000.0;
    if values.crop_width != 0 or values.crop_height != 0 {
        if values.crop_left < 0 or values.crop_top < 0 or
        values.crop_width <= 0 or values.crop_height <= 0 {
            return none;
        }
        recipe.crop.left = values.crop_left as usize;
        recipe.crop.top = values.crop_top as usize;
        recipe.crop.width = values.crop_width as usize;
        recipe.crop.height = values.crop_height as usize;
    }
    if not photo_geometry.valid_v2(recipe, source_width, source_height) {
        return none;
    }
    return recipe;
}

pub fn empty(): History {
    return {
        entries: [neutral()] ** 32,
        length: 0,
        cursor: 0
    };
}

pub fn reset(history: &History): void {
    history.entries[0] = neutral();
    history.length = 1;
    history.cursor = 0;
}

pub fn append(history: &History, values: Values): void {
    if history.length == 0 {
        reset(history);
    }
    if history.cursor == 31 {
        var index: usize = 2;
        while index < 32 {
            history.entries[index - 1] = history.entries[index];
            index = index + 1;
        }
        history.cursor = 30;
    }
    history.cursor = history.cursor + 1;
    history.entries[history.cursor] = values;
    history.length = history.cursor + 1;
}

pub fn can_undo(history: &const History): bool {
    return history.length > 0 and history.cursor > 0;
}

pub fn can_redo(history: &const History): bool {
    return history.length > 0 and history.cursor + 1 < history.length;
}

// A saved project may restore only complete, bounded preview recipes. The
// neutral first state identifies the unedited source under the pinned route.
pub fn valid(history: &const History): bool {
    if history.length == 0 or history.length > 32 or history.cursor >= history.length {
        return false;
    }
    var index: usize = 0;
    while index < history.length {
        const values = history.entries[index];
        if values.exposure_tenths < -40 or values.exposure_tenths > 40 or
        values.contrast_percent < -100 or values.contrast_percent > 100 or
        values.shadows_percent < -100 or values.shadows_percent > 100 or
        values.highlights_percent < -100 or values.highlights_percent > 100 or
        values.blacks_percent < -100 or values.blacks_percent > 100 or
        values.whites_percent < -100 or values.whites_percent > 100 or
        values.warmth_percent < -100 or values.warmth_percent > 100 or
        values.tint_percent < -100 or values.tint_percent > 100 or
        values.vibrance_percent < -100 or values.vibrance_percent > 100 or
        values.saturation_percent < -100 or values.saturation_percent > 100 or
        values.clarity_percent < -100 or values.clarity_percent > 100 or
        values.texture_percent < -100 or values.texture_percent > 100 {
            return false;
        }
        if values.transform_code < 1 or values.transform_code > 8 or
        not valid_hsl(values.hsl) or not valid_curve(values.curve) or
        not valid_grade(values.grade) or
        values.straighten_millidegrees < -17000 or
        values.straighten_millidegrees > 17000 or
        values.crop_left < 0 or values.crop_top < 0 or
        values.crop_width < 0 or values.crop_height < 0 {
            return false;
        }
        if values.crop_width == 0 or values.crop_height == 0 {
            if values.crop_left != 0 or values.crop_top != 0 or
            values.crop_width != 0 or values.crop_height != 0 {
                return false;
            }
        } else if values.crop_left > 10000 - values.crop_width or
        values.crop_top > 10000 - values.crop_height or
        values.crop_width > 10000 or values.crop_height > 10000 {
            return false;
        }
        if index == 0 and (values.exposure_tenths != 0 or values.contrast_percent != 0 or
            values.shadows_percent != 0 or values.highlights_percent != 0 or
            values.blacks_percent != 0 or values.whites_percent != 0 or
            values.warmth_percent != 0 or values.tint_percent != 0 or
            values.vibrance_percent != 0 or values.saturation_percent != 0 or
            values.clarity_percent != 0 or values.texture_percent != 0 or
            values.crop_left != 0 or values.crop_top != 0 or
            values.crop_width != 0 or values.crop_height != 0 or
            values.straighten_millidegrees != 0 or values.transform_code != 1
        ) {
            return false;
        }
        if index == 0 {
            if nonneutral_curve(values.curve) or nonneutral_grade(values.grade) {
                return false;
            }
            var band: usize = 0;
            while band < 8 {
                if hsl_percent(values.hsl, 0, band) != 0 or
                hsl_percent(values.hsl, 1, band) != 0 or
                hsl_percent(values.hsl, 2, band) != 0 {
                    return false;
                }
                band = band + 1;
            }
        }
        index = index + 1;
    }
    return true;
}
