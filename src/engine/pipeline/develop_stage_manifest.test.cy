import .engine.pipeline.develop_stage_manifest;

// Locate a row by name so coverage assertions never depend on table order.
fn contract_index(has_camera_matrix: bool, editable_white_balance: bool, name: string): usize {
    const stages = develop_stage_manifest.stage_contract(has_camera_matrix, editable_white_balance);
    var index: usize = 0;
    while index < stages.len() {
        if stages[index].name == name {
            return index;
        }
        index = index + 1;
    }
    return stages.len();
}

fn declared(name: string): bool {
    return contract_index(false, false, name) < 60;
}

test "the contract declares every develop capability the editor can name" {
    const stages = develop_stage_manifest.declared_stages();
    assert(stages.len() == 60);
    var index: usize = 0;
    while index < stages.len() {
        assert(stages[index].name.len() > 0 and stages[index].name.len() < 24);
        assert(stages[index].executable == 0);
        assert(stages[index].algorithm_version == 0);
        assert(stages[index].plan_position == 0);
        assert(stages[index].driven_controls == "");
        assert(stages[index].kind > 0 and stages[index].kind <= 12);
        assert(stages[index].input > 0 and stages[index].input <= 8);
        assert(stages[index].output > 0 and stages[index].output <= 8);
        assert(stages[index].status > 0 and stages[index].status <= 5);
        index = index + 1;
    }

    // Deferring a kernel is allowed; deleting a declaration is not. Every capability family a
    // traditional raw editor exposes stays named by the contract.
    var capture_colour: [:]string = ["exposure", "working_white", "white_point", "profile"];
    for capability in capture_colour {
        assert(declared(capability));
    }
    var tone: [:]string = ["blacks", "shadows", "contrast", "highlights", "whites", "tone_curve", "auto_tone"];
    for capability in tone {
        assert(declared(capability));
    }
    var chroma: [:]string = ["linear_chroma", "vibrance", "hue", "local_chroma", "luminance_bands", "hsl_grading", "channel_mixer"];
    for capability in chroma {
        assert(declared(capability));
    }
    var detail: [:]string = ["raw_denoise", "image_denoise", "capture_sharpening", "clarity", "texture", "defringe", "moire", "dehaze", "grain", "highlight_reconstruct"];
    for capability in detail {
        assert(declared(capability));
    }
    var geometry: [:]string = ["crop", "straighten", "perspective", "lens_distortion", "vignetting", "tca"];
    for capability in geometry {
        assert(declared(capability));
    }
    var masks: [:]string = ["mask_geometry", "sky_mask", "described_mask", "linear_gradient", "brush", "range_mask", "local_adjust"];
    for capability in masks {
        assert(declared(capability));
    }
    var output: [:]string = ["view_transform", "proof_transform", "output_transform", "working_to_linear_srgb", "srgb_clip", "srgb_transfer", "output_quantize", "output_profile", "precision_class", "gamut_map"];
    for capability in output {
        assert(declared(capability));
    }
    var analysis: [:]string = ["histogram", "clip_map", "region_statistics", "noise_estimate", "sharpness_estimate", "color_cast", "gamut_report"];
    for capability in analysis {
        assert(declared(capability));
    }
}

test "the composed plan marks executable stages and their plan position" {
    const plain = develop_stage_manifest.stage_contract(false, true);
    assert(plain.len() == 60);
    const exposure = plain[contract_index(false, true, "exposure")];
    assert(exposure.executable == 1);
    assert(exposure.algorithm_version == 1);
    assert(exposure.plan_position == 1);
    assert(exposure.edit_driven == 1);
    assert(exposure.driven_controls == "exposure");

    const profiled = develop_stage_manifest.stage_contract(true, true);
    const working_white = profiled[contract_index(true, true, "working_white")];
    assert(working_white.executable == 1);
    assert(working_white.plan_position == 2);
    assert(working_white.driven_controls == "temp,tint");
    assert(working_white.aux_ports == "camera color matrix");

    // A characterised source pinned to the as-shot white balance cannot compose the working-white
    // stage, so no white-balance control is executable for it.
    const as_shot_only = develop_stage_manifest.stage_contract(true, false);
    assert(as_shot_only[contract_index(true, false, "working_white")].executable == 0);

    var index: usize = 0;
    var composed: usize = 0;
    while index < profiled.len() {
        if profiled[index].executable == 1 {
            composed = composed + 1;
        }
        index = index + 1;
    }
    assert(composed == 4);
}

test "a composing stage is not automatically an executable control" {
    const contract = develop_stage_manifest.stage_contract(true, true);
    const chroma = contract[contract_index(true, true, "linear_chroma")];
    assert(chroma.executable == 1);
    assert(chroma.edit_driven == 0);
    assert(chroma.driven_controls == "");

    const output = contract[contract_index(true, true, "output_transform")];
    assert(output.executable == 1);
    assert(output.edit_driven == 0);

    // Deferred families stay declared: tone curve, HSL grading, and mask operands are named by the
    // contract but compose nothing yet.
    assert(contract[contract_index(true, true, "tone_curve")].executable == 0);
    assert(contract[contract_index(true, true, "hsl_grading")].executable == 0);
    assert(contract[contract_index(true, true, "local_adjust")].executable == 0);
    assert(develop_stage_manifest.composed_mask_operands() == 0);
}

test "a composed stage states the value modes its controls accept" {
    const contract = develop_stage_manifest.stage_contract(true, true);
    var index: usize = 0;
    while index < contract.len() {
        // Only a stage whose parameters come from develop edits may admit a mode.
        if contract[index].edit_driven == 1 {
            assert(contract[index].admitted_modes > 0);
        } else {
            assert(contract[index].admitted_modes == 0);
        }
        index = index + 1;
    }
    // The composed exposure stage applies a change to the working exposure, so a target value is
    // not yet a mode the plan executes. Working white accepts both spellings.
    assert(contract[contract_index(true, true, "exposure")].admitted_modes == 1);
    assert(contract[contract_index(true, true, "working_white")].admitted_modes == 3);
}
