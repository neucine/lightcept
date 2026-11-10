import .engine.pipeline.pipeline;
import .engine.pipeline.develop_stage_manifest;
import .engine.develop.contrast;

// The parameter half of the headless working-plan contract. This is a report
// of the Cyna compiler's actual parameter order, not a product slider table.
const parameter_contract_version: u32 = 1;
const descriptor_bytes: usize = 96;
const max_parameters: usize = 8;

pub struct ParameterEntry {
    pub stage: string;
    pub stage_id: u32;
    pub algorithm_version: u32;
    pub index: u32;
    pub name: string;
    pub units: string;
    pub minimum: f64;
    pub maximum: f64;
    pub neutral: f64;
}

fn entry(stage: string, stage_id: u32, index: u32, name: string, units: string, minimum: f64, maximum: f64, neutral: f64): ParameterEntry {
    return {
        stage: stage,
        stage_id: stage_id,
        algorithm_version: 1,
        index: index,
        name: name,
        units: units,
        minimum: minimum,
        maximum: maximum,
        neutral: neutral
    };
}

pub enum WorkingPlanKind: u32 {
    fused_working_srgb = 1,
    contrast_working_srgb = 2,
    split_sdr_output = 3,
}

// The wire API retains these numeric values.
// Output stages have no parameters in these plans.
pub fn rows(plan_kind: u32): [:]ParameterEntry {
    if plan_kind == WorkingPlanKind.contrast_working_srgb as u32 {
        return [
            entry("exposure", 1, 0, "ev", "EV", pipeline.working_exposure_min(), pipeline.working_exposure_max(), 0.0),
            entry("working_white", 2, 1, "red_gain", "gain", pipeline.working_gain_min(), pipeline.working_gain_max(), 1.0),
            entry("working_white", 2, 2, "green_gain", "gain", pipeline.working_gain_min(), pipeline.working_gain_max(), 1.0),
            entry("working_white", 2, 3, "blue_gain", "gain", pipeline.working_gain_min(), pipeline.working_gain_max(), 1.0),
            entry("contrast", 5, 4, "slope", "ratio", contrast.slope_min(), contrast.slope_max(), 1.0),
            entry("linear_chroma", 3, 5, "factor", "ratio", pipeline.working_chroma_min(), pipeline.working_chroma_max(), 1.0)
        ];
    }
    return [
        entry("exposure", 1, 0, "ev", "EV", pipeline.working_exposure_min(), pipeline.working_exposure_max(), 0.0),
        entry("working_white", 2, 1, "red_gain", "gain", pipeline.working_gain_min(), pipeline.working_gain_max(), 1.0),
        entry("working_white", 2, 2, "green_gain", "gain", pipeline.working_gain_min(), pipeline.working_gain_max(), 1.0),
        entry("working_white", 2, 3, "blue_gain", "gain", pipeline.working_gain_min(), pipeline.working_gain_max(), 1.0),
        entry("linear_chroma", 3, 4, "factor", "ratio", pipeline.working_chroma_min(), pipeline.working_chroma_max(), 1.0)
    ];
}

fn write_float(base: usize, offset: usize, value: f64): void {
    unchecked {
        *((base + offset) as! *f64) = value;
    }
}

fn write_row(base: usize, index: usize, row: ParameterEntry): void {
    const slot = base + index * descriptor_bytes;
    develop_stage_manifest.write_padded(slot, 0, row.stage, 24);
    develop_stage_manifest.write_number(slot, 24, row.stage_id);
    develop_stage_manifest.write_number(slot, 28, row.algorithm_version);
    develop_stage_manifest.write_number(slot, 32, row.index);
    develop_stage_manifest.write_padded(slot, 36, row.name, 24);
    develop_stage_manifest.write_padded(slot, 60, row.units, 12);
    write_float(slot, 72, row.minimum);
    write_float(slot, 80, row.maximum);
    write_float(slot, 88, row.neutral);
}

// Status: 0 success, 3 shape, 4 unknown plan kind. Fixed-size output is
// completely initialized so stale memory cannot be mistaken for a row.
fn describe_working_plan_parameters(plan_kind: u32, output: *u8, output_len: usize, count: *u32, count_len: usize, version: *u32, version_len: usize): i32 {
    if output_len as usize != max_parameters * descriptor_bytes or count_len as usize != 1 or version_len as usize != 1 {
        return 3;
    }
    if plan_kind < WorkingPlanKind.fused_working_srgb as u32 or plan_kind > WorkingPlanKind.split_sdr_output as u32 {
        return 4;
    }
    const parameters = rows(plan_kind as u32);
    const base = output as! usize;
    var byte: usize = 0;
    while byte < max_parameters * descriptor_bytes {
        unchecked {
            *((base + byte) as! *u8) = 0;
        }
        byte = byte + 1;
    }
    var index: usize = 0;
    while index < parameters.len() {
        write_row(base, index, parameters[index]);
        index = index + 1;
    }
    unchecked {
        *(count as! *u32) = parameters.len() as u32;
        *(version as! *u32) = parameter_contract_version as u32;
    }
    return 0;
}
