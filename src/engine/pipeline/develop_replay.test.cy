import .engine.pipeline.develop_replay;
import .engine.pipeline.develop_sample;
import .engine.develop.edit_plan;
import .engine.develop.tone_curve;
import .engine.develop.channel_mixer;

fn curve(middle: f64): tone_curve.CurveAsset {
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: middle
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    return {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
}

fn source(): develop_replay.WorkingSourceIdentity {
    var source_hash: [32]u8 = [0] ** 32;
    var working_hash: [32]u8 = [0] ** 32;
    source_hash[0] = 17;
    source_hash[31] = 42;
    working_hash[0] = 9;
    working_hash[31] = 80;
    return {
        version: 1,
        source_sha256: source_hash,
        working_contract_sha256: working_hash,
        width: 6000,
        height: 4000,
        domain: 4
    };
}

test "exact headless replay pin repeats the same composed sample" {
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
    var mixer = channel_mixer.neutral_asset();
    mixer.red_from_green = 0.25;
    const asset = curve(0.6);
    const pin = develop_replay.capture(compiled.plan, mixer, curve(0.6));
    assert(pin.valid and develop_replay.matches(&pin, compiled.plan, mixer, &asset));
    const pixel: develop_sample.SampleRgb = {
        red: 0.2,
        green: 0.15,
        blue: 0.1
    };
    const first = develop_replay.apply_pinned(&pin, compiled.plan, mixer, asset, pixel);
    const second = develop_replay.apply_pinned(&pin, compiled.plan, mixer, curve(0.6), pixel);
    assert(first.valid and second.valid and first.status == 0 and second.status == 0);
    assert(first.pixel.red == second.pixel.red and first.pixel.green == second.pixel.green and first.pixel.blue == second.pixel.blue);
}

test "replay pin rejects changed plan mixer and curve before processing" {
    const plan = edit_plan.neutral_plan();
    const mixer = channel_mixer.neutral_asset();
    const asset = curve(0.6);
    const pin = develop_replay.capture(plan, mixer, curve(0.6));
    assert(pin.valid);
    const pixel: develop_sample.SampleRgb = {
        red: 0.2,
        green: 0.2,
        blue: 0.2
    };
    var changed_plan = plan;
    changed_plan.exposure_ev = -0.0;
    const plan_rejected = develop_replay.apply_pinned(&pin, changed_plan, mixer, curve(0.6), pixel);
    assert(not plan_rejected.valid and plan_rejected.status == 8);
    var changed_mixer = mixer;
    changed_mixer.red_from_green = 0.25;
    const mixer_rejected = develop_replay.apply_pinned(&pin, plan, changed_mixer, curve(0.6), pixel);
    assert(not mixer_rejected.valid and mixer_rejected.status == 8);
    const curve_rejected = develop_replay.apply_pinned(&pin, plan, mixer, curve(0.6000000000000001), pixel);
    assert(not curve_rejected.valid and curve_rejected.status == 8);
    assert(curve_rejected.pixel.red == 0.0 and curve_rejected.pixel.green == 0.0 and curve_rejected.pixel.blue == 0.0);
}

test "invalid assets cannot produce a replay pin" {
    const nodes: [:]tone_curve.CurveNode = [{
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
    const bad: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
    const pin = develop_replay.capture(edit_plan.neutral_plan(), channel_mixer.neutral_asset(), bad);
    assert(not pin.valid);
}

test "source-bound replay accepts exact source working contract and edit" {
    const identity = source();
    const plan = edit_plan.neutral_plan();
    const mixer = channel_mixer.neutral_asset();
    const pin = develop_replay.capture_source(identity, plan, mixer, curve(0.6));
    assert(pin.valid);
    const same = curve(0.6);
    assert(develop_replay.matches_source(&pin, identity, plan, mixer, &same));
    const pixel: develop_sample.SampleRgb = {
        red: 0.2,
        green: 0.2,
        blue: 0.2
    };
    const result = develop_replay.apply_source_pinned(&pin, identity, plan, mixer, curve(0.6), pixel);
    assert(result.valid and result.status == 0);
}

test "source-bound replay rejects changed bytes contract and geometry" {
    const original = source();
    const plan = edit_plan.neutral_plan();
    const mixer = channel_mixer.neutral_asset();
    const pin = develop_replay.capture_source(original, plan, mixer, curve(0.6));
    const pixel: develop_sample.SampleRgb = {
        red: 0.2,
        green: 0.2,
        blue: 0.2
    };
    var changed = source();
    changed.source_sha256[31] = 43;
    const bytes = develop_replay.apply_source_pinned(&pin, changed, plan, mixer, curve(0.6), pixel);
    assert(not bytes.valid and bytes.status == 9 and bytes.pixel.red == 0.0);
    changed = source();
    changed.working_contract_sha256[31] = 81;
    const working = develop_replay.apply_source_pinned(&pin, changed, plan, mixer, curve(0.6), pixel);
    assert(not working.valid and working.status == 9);
    changed = source();
    changed.width = 6001;
    const geometry = develop_replay.apply_source_pinned(&pin, changed, plan, mixer, curve(0.6), pixel);
    assert(not geometry.valid and geometry.status == 9);
    var changed_plan = plan;
    changed_plan.exposure_ev = 1.0;
    const edit = develop_replay.apply_source_pinned(&pin, original, changed_plan, mixer, curve(0.6), pixel);
    assert(not edit.valid and edit.status == 8);
}

test "source identity enforces digest and pixel resource bounds" {
    var candidate = source();
    assert(develop_replay.valid_source(candidate));
    candidate.width = 100000;
    candidate.height = 100000;
    assert(not develop_replay.valid_source(candidate));
    candidate = source();
    candidate.source_sha256 = [0] ** 32;
    assert(not develop_replay.valid_source(candidate));
    candidate = source();
    candidate.domain = 3;
    assert(not develop_replay.valid_source(candidate));
}
