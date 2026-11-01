import .engine.pipeline.pipeline;
import .engine.develop.black_point;
import .engine.develop.contrast;
import .engine.develop.shadows;
import .engine.develop.highlights;
import .engine.develop.vibrance;
import .engine.develop.whites;

// Cyna-only logical develop plan. It declares edit meaning and stage order;
// no image buffer, output transform, bridge, or execution backend is involved.
pub const plan_version: u32 = 1;
pub const edit_exposure: u32 = 1;
pub const edit_blacks: u32 = 2;
pub const edit_contrast: u32 = 3;
pub const edit_linear_chroma: u32 = 4;
pub const edit_shadows: u32 = 5;
pub const edit_highlights: u32 = 6;
pub const edit_vibrance: u32 = 7;
pub const edit_whites: u32 = 8;
const scene_linear_rec2020: u32 = 4;
pub const mode_target: u32 = 1;
pub const mode_delta: u32 = 2;

pub fn exposure_min(): f64 {
    return pipeline.working_exposure_min() as f64;
}
pub fn exposure_max(): f64 {
    return pipeline.working_exposure_max() as f64;
}
pub fn chroma_min(): f64 {
    return pipeline.working_chroma_min() as f64;
}
pub fn chroma_max(): f64 {
    return pipeline.working_chroma_max() as f64;
}

pub struct EditDefinition {
    pub id: u32;
    pub name: string;
    pub stage_id: u32;
    pub stage_version: u32;
    pub units: string;
    pub minimum: f64;
    pub maximum: f64;
    pub neutral: f64;
}

pub struct StageUse {
    pub id: u32;
    pub version: u32;
    pub name: string;
    pub input_domain: u32;
    pub output_domain: u32;
}

pub struct EditRequest {
    pub id: u32;
    pub mode: u32;
    pub value: f64;
}

pub struct DevelopPlan {
    pub version: u32;
    pub exposure_ev: f64;
    pub black_offset: f64;
    pub shadows_strength: f64;
    pub contrast_percent: f64;
    pub contrast_slope: f64;
    pub highlights_strength: f64;
    pub whites_strength: f64;
    pub linear_chroma: f64;
    pub vibrance_strength: f64;
}

pub struct CompileResult {
    pub valid: bool;
    // 0 success, 1 unknown edit, 2 unsupported mode, 3 value outside range.
    pub status: u32;
    pub failure_index: usize;
    pub plan: DevelopPlan;
}

fn definition(id: u32, name: string, stage_id: u32, units: string, minimum: f64, maximum: f64, neutral: f64): EditDefinition {
    return {
        id: id,
        name: name,
        stage_id: stage_id,
        stage_version: 1,
        units: units,
        minimum: minimum,
        maximum: maximum,
        neutral: neutral
    };
}

// Internal ids are stable within this version and are independent of UI labels.
pub fn definitions(): [:]EditDefinition {
    return [
        definition(edit_exposure, "exposure", 1, "EV", exposure_min(), exposure_max(), 0.0),
        definition(edit_blacks, "blacks", 10, "linear-white", black_point.minimum(), black_point.maximum(), 0.0),
        definition(edit_shadows, "shadows", 11, "strength", shadows.minimum(), shadows.maximum(), 0.0),
        definition(edit_contrast, "contrast", 5, "percent", -100.0, 100.0, 0.0),
        definition(edit_highlights, "highlights", 12, "strength", highlights.minimum(), highlights.maximum(), 0.0),
        definition(edit_whites, "whites", 14, "strength", whites.minimum(), whites.maximum(), 0.0),
        definition(edit_linear_chroma, "linear_chroma", 3, "ratio", chroma_min(), chroma_max(), 1.0),
        definition(edit_vibrance, "vibrance", 13, "strength", vibrance.minimum(), vibrance.maximum(), 0.0)
    ];
}

fn stage(id: u32, name: string): StageUse {
    return {
        id: id,
        version: 1,
        name: name,
        input_domain: scene_linear_rec2020,
        output_domain: scene_linear_rec2020
    };
}

// This order is photographic policy, independent of edit submission order.
pub fn stage_order(): [:]StageUse {
    return [stage(1, "exposure"), stage(10, "blacks"), stage(11, "shadows"), stage(5, "contrast"), stage(12, "highlights"), stage(14, "whites"), stage(3, "linear_chroma"), stage(13, "vibrance")];
}

pub fn neutral_plan(): DevelopPlan {
    return {
        version: plan_version,
        exposure_ev: 0.0,
        black_offset: 0.0,
        shadows_strength: 0.0,
        contrast_percent: 0.0,
        contrast_slope: 1.0,
        highlights_strength: 0.0,
        whites_strength: 0.0,
        linear_chroma: 1.0,
        vibrance_strength: 0.0
    };
}

fn rejected(status: u32, index: usize): CompileResult {
    return {
        valid: false,
        status: status,
        failure_index: index,
        plan: neutral_plan()
    };
}

pub fn compile(requests: [:]EditRequest): CompileResult {
    const available = definitions();
    var plan = neutral_plan();
    var index: usize = 0;
    while index < requests.len() {
        const request = requests[index];
        var found: usize = 0;
        while found < available.len() and available[found].id != request.id {
            found = found + 1;
        }
        if found == available.len() {
            return rejected(1, index);
        }
        if request.mode != mode_target and request.mode != mode_delta {
            return rejected(2, index);
        }
        var current: f64 = 0.0;
        if request.id == edit_exposure {
            current = plan.exposure_ev;
        }
        if request.id == edit_blacks {
            current = plan.black_offset;
        }
        if request.id == edit_shadows {
            current = plan.shadows_strength;
        }
        if request.id == edit_contrast {
            current = plan.contrast_percent;
        }
        if request.id == edit_highlights {
            current = plan.highlights_strength;
        }
        if request.id == edit_whites {
            current = plan.whites_strength;
        }
        if request.id == edit_linear_chroma {
            current = plan.linear_chroma;
        }
        if request.id == edit_vibrance {
            current = plan.vibrance_strength;
        }
        var value = request.value;
        if request.mode == mode_delta {
            value = current + request.value;
        }
        if not (value >= available[found].minimum and value <= available[found].maximum) {
            return rejected(3, index);
        }
        if request.id == edit_exposure {
            plan.exposure_ev = value;
        }
        if request.id == edit_blacks {
            plan.black_offset = value;
        }
        if request.id == edit_shadows {
            plan.shadows_strength = value;
        }
        if request.id == edit_contrast {
            plan.contrast_percent = value;
            plan.contrast_slope = contrast.slope_from_percent_native(value);
        }
        if request.id == edit_linear_chroma {
            plan.linear_chroma = value;
        }
        if request.id == edit_highlights {
            plan.highlights_strength = value;
        }
        if request.id == edit_whites {
            plan.whites_strength = value;
        }
        if request.id == edit_vibrance {
            plan.vibrance_strength = value;
        }
        index = index + 1;
    }
    return {
        valid: true,
        status: 0,
        failure_index: requests.len(),
        plan: plan
    };
}
