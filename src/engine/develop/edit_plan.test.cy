import .engine.develop.edit_plan;
import .engine.develop.black_point;
import .engine.develop.contrast;

test "logical edit plan declares typed stages without rendering" {
    const definitions = edit_plan.definitions();
    const stages = edit_plan.stage_order();
    assert(definitions.len() == 8 and stages.len() == 8);
    assert(stages[0].name == "exposure" and stages[1].name == "blacks");
    assert(stages[2].name == "shadows" and stages[3].name == "contrast");
    assert(stages[4].name == "highlights" and stages[5].name == "whites");
    assert(stages[6].name == "linear_chroma" and stages[7].name == "vibrance");
    var index: usize = 0;
    while index < stages.len() {
        assert(stages[index].input_domain == 4 and stages[index].output_domain == 4);
        assert(stages[index].version == 1 and stages[index].id == definitions[index].stage_id);
        index = index + 1;
    }
    assert(definitions[1].minimum == black_point.minimum() as f64);
    assert(definitions[1].maximum == black_point.maximum() as f64);
}

test "logical edit compilation resolves target and delta without pixel buffers" {
    const requests: [:]edit_plan.EditRequest = [{
            id: edit_plan.edit_contrast,
            mode: edit_plan.mode_target,
            value: 40.0
        }, {
            id: edit_plan.edit_exposure,
            mode: edit_plan.mode_delta,
            value: 0.5
        }, {
            id: edit_plan.edit_blacks,
            mode: edit_plan.mode_target,
            value: 0.0625
        }, {
            id: edit_plan.edit_shadows,
            mode: edit_plan.mode_target,
            value: 0.5
        }, {
            id: edit_plan.edit_contrast,
            mode: edit_plan.mode_delta,
            value: -15.0
        }, {
            id: edit_plan.edit_highlights,
            mode: edit_plan.mode_target,
            value: -0.5
        }, {
            id: edit_plan.edit_whites,
            mode: edit_plan.mode_target,
            value: 0.25
        }, {
            id: edit_plan.edit_linear_chroma,
            mode: edit_plan.mode_target,
            value: 1.25
        }, {
            id: edit_plan.edit_vibrance,
            mode: edit_plan.mode_target,
            value: 0.4
        }
    ];
    const result = edit_plan.compile(requests);
    assert(result.valid and result.status == 0 and result.failure_index == 9);
    assert(result.plan.version == edit_plan.plan_version);
    assert(result.plan.exposure_ev == 0.5 and result.plan.black_offset == 0.0625);
    assert(result.plan.contrast_percent == 25.0 and result.plan.contrast_slope == 1.25);
    assert(result.plan.shadows_strength == 0.5 and result.plan.highlights_strength == -0.5);
    assert(result.plan.whites_strength == 0.25);
    assert(result.plan.linear_chroma == 1.25);
    assert(result.plan.vibrance_strength == 0.4);
    const pixel = black_point.apply(0.2, 0.2, 0.2, result.plan.black_offset);
    const toned = contrast.apply(pixel.red as c_double, pixel.green as c_double, pixel.blue as c_double, result.plan.contrast_slope as c_double);
    assert(toned.red == toned.green and toned.green == toned.blue);
}

test "invalid edits fail atomically with the offending index" {
    const unknown: [:]edit_plan.EditRequest = [{
        id: 99,
        mode: 1,
        value: 1.0
    }];
    assert(edit_plan.compile(unknown).status == 1);
    const bad_mode: [:]edit_plan.EditRequest = [{
        id: 1,
        mode: 3,
        value: 1.0
    }];
    assert(edit_plan.compile(bad_mode).status == 2);
    const overflow: [:]edit_plan.EditRequest = [{
            id: 1,
            mode: 1,
            value: 2.0
        }, {
            id: 2,
            mode: 1,
            value: 0.2
        }
    ];
    const result = edit_plan.compile(overflow);
    assert(not result.valid and result.status == 3 and result.failure_index == 1);
    assert(result.plan.exposure_ev == 0.0 and result.plan.black_offset == 0.0);
}
