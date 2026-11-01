import .engine.pipeline.develop_batch;
import .engine.pipeline.develop_sample;
import .engine.develop.edit_plan;
import .engine.color.output_color;

fn no_cancel(index: usize): bool {
    return false;
}

fn one_status(): u32 {
    const input: [1]develop_sample.SampleRgb = [{
        red: 0.2,
        green: 0.2,
        blue: 0.2
    }];
    var output: [1]develop_sample.SampleRgb = [{
        red: 9.0,
        green: 9.0,
        blue: 9.0
    }];
    return develop_batch.apply(edit_plan.neutral_plan(), input[..], output[..], 1, no_cancel).status;
}

test "neutral batch does not reject shape" {
    assert(one_status() != 1);
}
test "neutral batch does not reject budget" {
    assert(one_status() != 2);
}
test "neutral batch does not cancel" {
    assert(one_status() != 3);
}
test "neutral batch does not reject sample" {
    assert(one_status() != 4);
}

test "batch reports success for one neutral sample" {
    const input: [1]develop_sample.SampleRgb = [{
        red: 0.2,
        green: 0.2,
        blue: 0.2
    }];
    var output: [1]develop_sample.SampleRgb = [{
        red: 9.0,
        green: 9.0,
        blue: 9.0
    }];
    const result = develop_batch.apply(edit_plan.neutral_plan(), input[..], output[..], 1, no_cancel);
    assert(result.valid and result.status == 0);
}

test "batch copies one neutral sample to output" {
    const input: [1]develop_sample.SampleRgb = [{
        red: 0.2,
        green: 0.2,
        blue: 0.2
    }];
    var output: [1]develop_sample.SampleRgb = [{
        red: 9.0,
        green: 9.0,
        blue: 9.0
    }];
    const result = develop_batch.apply(edit_plan.neutral_plan(), input[..], output[..], 1, no_cancel);
    assert(output[0].red == 0.2);
}

test "bounded batch applies the fixed plan to independent working samples" {
    const requests: [:]edit_plan.EditRequest = [{
            id: edit_plan.edit_exposure,
            mode: edit_plan.mode_target,
            value: 1.0
        }, {
            id: edit_plan.edit_blacks,
            mode: edit_plan.mode_target,
            value: 0.05
        }
    ];
    const compiled = edit_plan.compile(requests);
    assert(compiled.valid);
    const input: [3]develop_sample.SampleRgb = [{
            red: 0.1,
            green: 0.1,
            blue: 0.1
        }, {
            red: 0.5,
            green: 0.5,
            blue: 0.5
        }, {
            red: -0.1,
            green: -0.1,
            blue: -0.1
        }
    ];
    var output: [3]develop_sample.SampleRgb = [{
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }, {
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }, {
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }
    ];
    const result = develop_batch.apply(compiled.plan, input[..], output[..], 3, no_cancel);
    assert(result.valid and result.status == 0 and result.processed == 3);
    assert(output[0].red > 0.149999 and output[0].red < 0.150001);
    assert(output[1].red == 0.95 and output[2].red == -0.25);
}

test "cancellation before commit preserves every output sample" {
    const input: [2]develop_sample.SampleRgb = [{
            red: 0.1,
            green: 0.1,
            blue: 0.1
        }, {
            red: 0.2,
            green: 0.2,
            blue: 0.2
        }
    ];
    var output: [2]develop_sample.SampleRgb = [{
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }, {
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }
    ];
    const result = develop_batch.apply(edit_plan.neutral_plan(), input[..], output[..], 2, | index | {
        return index >= 1;
    });
    assert(not result.valid and result.status == 3 and result.failure_index == 1);
    assert(output[0].red == 9.0 and output[1].red == 9.0);
}

test "invalid sample shape and budget preserve caller output" {
    const infinity = output_color.exposure_gain_native(1024.0);
    const input: [2]develop_sample.SampleRgb = [{
            red: 0.1,
            green: 0.1,
            blue: 0.1
        }, {
            red: infinity,
            green: 0.2,
            blue: 0.2
        }
    ];
    var output: [2]develop_sample.SampleRgb = [{
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }, {
            red: 9.0,
            green: 9.0,
            blue: 9.0
        }
    ];
    const invalid = develop_batch.apply(edit_plan.neutral_plan(), input[..], output[..], 2, no_cancel);
    assert(not invalid.valid and invalid.status == 4 and invalid.failure_index == 1);
    assert(output[0].red == 9.0 and output[1].red == 9.0);
    const budget = develop_batch.apply(edit_plan.neutral_plan(), input[..], output[..], 1, no_cancel);
    assert(not budget.valid and budget.status == 2 and output[0].red == 9.0);
    var one: [1]develop_sample.SampleRgb = [{
        red: 0.0,
        green: 0.0,
        blue: 0.0
    }];
    const shape = develop_batch.apply(edit_plan.neutral_plan(), input[..], one[..], 2, no_cancel);
    assert(not shape.valid and shape.status == 1);
}
