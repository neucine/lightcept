import .engine.core.core;
import .engine.develop.edit_plan;
import .engine.pipeline.develop_sample;
import .engine.color.output_color;
import .engine.develop.tone_curve;
import .engine.develop.channel_mixer;

test "neutral scalar plan retains signed channels and highlight headroom" {
    const pixel: develop_sample.SampleRgb = {
        red: -0.125,
        green: 0.18,
        blue: 2.0
    };
    const result = develop_sample.apply(edit_plan.neutral_plan(), pixel);
    assert(result.valid and result.status == 0);
    assert(result.pixel.red == pixel.red and result.pixel.green == pixel.green and result.pixel.blue == pixel.blue);
}

test "compiled scalar plan follows fixed exposure black and white order" {
    const requests: [:]edit_plan.EditRequest = [{
            id: edit_plan.edit_whites,
            mode: edit_plan.mode_target,
            value: 1.0
        }, {
            id: edit_plan.edit_blacks,
            mode: edit_plan.mode_target,
            value: 0.05
        }, {
            id: edit_plan.edit_exposure,
            mode: edit_plan.mode_target,
            value: 1.0
        }
    ];
    const compiled = edit_plan.compile(requests);
    assert(compiled.valid);
    const dark: develop_sample.SampleRgb = {
        red: 0.1,
        green: 0.1,
        blue: 0.1
    };
    const dark_result = develop_sample.apply(compiled.plan, dark);
    assert(dark_result.valid and dark_result.pixel.red > 0.149999 and dark_result.pixel.red < 0.150001);
    const bright: develop_sample.SampleRgb = {
        red: 0.5,
        green: 0.5,
        blue: 0.5
    };
    const bright_result = develop_sample.apply(compiled.plan, bright);
    // Exposure 0.5 -> 1.0, black -> 0.95, whites -> 1.4.
    assert(bright_result.valid and bright_result.pixel.red > 1.399999 and bright_result.pixel.red < 1.400001);
}

test "scalar executor rejects altered plan version" {
    var plan = edit_plan.neutral_plan();
    plan.version = 99;
    const pixel: develop_sample.SampleRgb = {
        red: 0.2,
        green: 0.2,
        blue: 0.2
    };
    const result = develop_sample.apply(plan, pixel);
    assert(not result.valid and result.status == 1);
}

test "scalar executor rejects altered contrast mapping" {
    var plan = edit_plan.neutral_plan();
    plan.contrast_slope = 2.0;
    const pixel: develop_sample.SampleRgb = {
        red: 0.2,
        green: 0.2,
        blue: 0.2
    };
    const result = develop_sample.apply(plan, pixel);
    assert(not result.valid and result.status == 1);
}

test "scalar executor rejects nonfinite input" {
    const infinity = core.positive_infinity64();
    const pixel: develop_sample.SampleRgb = {
        red: infinity,
        green: 0.2,
        blue: 0.2
    };
    const result = develop_sample.apply(edit_plan.neutral_plan(), pixel);
    assert(not result.valid and result.status == 2);
    const not_a_number = infinity - infinity;
    const nan_pixel: develop_sample.SampleRgb = {
        red: not_a_number,
        green: 0.2,
        blue: 0.2
    };
    const nan_result = develop_sample.apply(edit_plan.neutral_plan(), nan_pixel);
    assert(not nan_result.valid and nan_result.status == 2);
}

test "scalar executor discards nonfinite stage output" {
    const requests: [:]edit_plan.EditRequest = [{
            id: edit_plan.edit_exposure,
            mode: edit_plan.mode_target,
            value: 1.0
        }
    ];
    const compiled = edit_plan.compile(requests);
    assert(compiled.valid);
    const large = output_color.exposure_gain_native(1023.0);
    const pixel: develop_sample.SampleRgb = {
        red: large,
        green: 0.0,
        blue: 0.0
    };
    const result = develop_sample.apply(compiled.plan, pixel);
    assert(not result.valid and result.status == 3);
    assert(result.pixel.red == 0.0 and result.pixel.green == 0.0 and result.pixel.blue == 0.0);
}

test "optional curve runs after scalar whites and rejects invalid assets" {
    const requests: [:]edit_plan.EditRequest = [{
            id: edit_plan.edit_whites,
            mode: edit_plan.mode_target,
            value: 1.0
        }
    ];
    const compiled = edit_plan.compile(requests);
    assert(compiled.valid);
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.6
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const curve: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
    const pixel: develop_sample.SampleRgb = {
        red: 0.5,
        green: 0.5,
        blue: 0.5
    };
    const result = develop_sample.apply_with_curve(compiled.plan, curve, pixel);
    // Whites sees its exact 0.5 pivot first, then the curve maps 0.5 to 0.6.
    assert(result.valid and result.pixel.red > 0.599999 and result.pixel.red < 0.600001);
    const invalid_nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.0,
            output: 0.5
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const invalid: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: invalid_nodes
    };
    const rejected = develop_sample.apply_with_curve(edit_plan.neutral_plan(), invalid, pixel);
    assert(not rejected.valid and rejected.status == 4);
}

test "mixer runs before luminance curve in the asset chain" {
    var mixer = channel_mixer.neutral_asset();
    mixer.red_from_green = 1.0;
    mixer.green_from_red = 1.0;
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.6
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const curve: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
    const pixel: develop_sample.SampleRgb = {
        red: 0.8,
        green: 0.2,
        blue: 0.2
    };
    const result = develop_sample.apply_with_assets(edit_plan.neutral_plan(), mixer, curve, pixel);
    // Swapped RGB has Y=0.6068. The curve maps Y to 0.68544, an offset of 0.07864.
    assert(result.valid and result.pixel.red > 0.278639 and result.pixel.red < 0.278641);
    assert(result.pixel.green > 0.878639 and result.pixel.green < 0.878641);
}
