import .engine.pipeline.color_solution_plan;
import .engine.pipeline.color_solution_execute;
import .engine.develop.rgb_gradation;
import .engine.develop.chroma_map;

fn no_cancel(context: usize): bool {
    return false;
}

fn hash(value: u8): [32]u8 {
    var result: [32]u8 = [0] ** 32;
    result[0] = value;
    return result;
}

fn curves(midpoint: f64): rgb_gradation.Asset {
    const red: [:]rgb_gradation.Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: midpoint
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const identity: [:]rgb_gradation.Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const blue: [:]rgb_gradation.Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.25
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    return {
        version: rgb_gradation.algorithm_version,
        domain: rgb_gradation.srgb_domain(),
        red: red,
        green: identity,
        blue: blue
    };
}

fn request(asset_hash: [32]u8): color_solution_plan.Request {
    const zero: [32]u8 = [0] ** 32;
    const steps: [:]color_solution_plan.Operation = [{
        slot: color_solution_plan.GRADATION,
        algorithm_version: rgb_gradation.algorithm_version,
        input_domain: color_solution_plan.ENCODED_SRGB_D65,
        output_domain: color_solution_plan.ENCODED_SRGB_D65,
        asset_sha256: asset_hash,
        source_profile_sha256: zero
    }];
    return {
        route_version: 2,
        source_sha256: hash(1),
        source_profile_sha256: zero,
        initial_domain: color_solution_plan.ENCODED_SRGB_D65,
        branch_sha256: hash(2),
        width: 3,
        height: 1,
        max_pixels: 3,
        operations: steps
    };
}

fn scene_request(asset_hash: [32]u8, width: usize, height: usize): color_solution_plan.Request {
    const zero: [32]u8 = [0] ** 32;
    const steps: [:]color_solution_plan.Operation = [{
        slot: color_solution_plan.SCENE_TO_SRGB_VIEW,
        algorithm_version: 1,
        input_domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        output_domain: color_solution_plan.ENCODED_SRGB_D65,
        asset_sha256: zero,
        source_profile_sha256: zero
    }, {
        slot: color_solution_plan.SRGB_VIEW_GRADATION,
        algorithm_version: rgb_gradation.algorithm_version,
        input_domain: color_solution_plan.ENCODED_SRGB_D65,
        output_domain: color_solution_plan.ENCODED_SRGB_D65,
        asset_sha256: asset_hash,
        source_profile_sha256: zero
    }];
    return {
        route_version: 3,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        initial_domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        branch_sha256: hash(23),
        width: width,
        height: height,
        max_pixels: width * height,
        operations: steps
    };
}

fn chroma_asset(primaries: u32): chroma_map.ChromaMapAsset {
    const table: [:]chroma_map.Delta = [{
            cb: 0.0,
            cr: 0.0
        }, {
            cb: 0.0,
            cr: 0.0
        }, {
            cb: 0.2,
            cr: 0.0
        }, {
            cb: 0.2,
            cr: 0.0
        }
    ];
    return {
        version: chroma_map.algorithm_version,
        primaries: primaries,
        to_opponent: [0.3333333333333333, 0.3333333333333333,
            0.3333333333333333, 1.0, -1.0, 0.0, 0.0, 1.0, -1.0
        ],
        from_opponent: [1.0, 0.6666666666666666, 0.3333333333333333,
            1.0, -0.3333333333333333, 0.3333333333333333,
            1.0, -0.3333333333333333, -0.6666666666666666
        ],
        cb_origin: -2.0,
        cr_origin: -2.0,
        cb_step: 4.0,
        cr_step: 4.0,
        cb_count: 2,
        cr_count: 2,
        deltas: table,
        neutral_radius: 0.5,
        strength: 1.0
    };
}

fn chroma_request(chroma_hash: [32]u8, gradation_hash: [32]u8): color_solution_plan.Request {
    const zero: [32]u8 = [0] ** 32;
    const steps: [:]color_solution_plan.Operation = [{
        slot: color_solution_plan.CHROMA_MAP,
        algorithm_version: 1,
        input_domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        output_domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        asset_sha256: chroma_hash,
        source_profile_sha256: zero
    }, {
        slot: color_solution_plan.SCENE_TO_SRGB_VIEW,
        algorithm_version: 1,
        input_domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        output_domain: color_solution_plan.ENCODED_SRGB_D65,
        asset_sha256: zero,
        source_profile_sha256: zero
    }, {
        slot: color_solution_plan.SRGB_VIEW_GRADATION,
        algorithm_version: rgb_gradation.algorithm_version,
        input_domain: color_solution_plan.ENCODED_SRGB_D65,
        output_domain: color_solution_plan.ENCODED_SRGB_D65,
        asset_sha256: gradation_hash,
        source_profile_sha256: zero
    }];
    return {
        route_version: 4,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        initial_domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        branch_sha256: hash(23),
        width: 1,
        height: 1,
        max_pixels: 1,
        operations: steps
    };
}

test "two caller assets execute through the same view route and replay" {
    const warm = curves(0.75);
    const cool = curves(0.25);
    var warm_hash: [32]u8 = [0] ** 32;
    var cool_hash: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&warm, warm_hash[0..], no_cancel, 0) == 0);
    assert(rgb_gradation.digest(&cool, cool_hash[0..], no_cancel, 0) == 0);
    assert(warm_hash != cool_hash);
    const warm_request = request(warm_hash);
    const cool_request = request(cool_hash);
    const warm_plan = color_solution_plan.compile(&warm_request);
    const cool_plan = color_solution_plan.compile(&cool_request);
    assert(warm_plan.valid and cool_plan.valid);
    const input: [9]f32 = [0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0];
    var warm_output: [9]f32 = [9.0] ** 9;
    var cool_output: [9]f32 = [9.0] ** 9;
    var replay: [9]f32 = [9.0] ** 9;
    assert(color_solution_execute.render(warm_plan, &warm_request, &warm,
        input[..], warm_output[..], no_cancel, 0
    ) == 0);
    assert(color_solution_execute.render(cool_plan, &cool_request, &cool,
        input[..], cool_output[..], no_cancel, 0
    ) == 0);
    assert(color_solution_execute.render(warm_plan, &warm_request, &warm,
        input[..], replay[..], no_cancel, 0
    ) == 0);
    assert(warm_output == replay and warm_output != cool_output);
    assert(warm_output[3] == 0.75 and cool_output[3] == 0.25);
}

test "wrong asset and domain reject before output writes" {
    const warm = curves(0.75);
    const cool = curves(0.25);
    var warm_hash: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&warm, warm_hash[0..], no_cancel, 0) == 0);
    var selected = request(warm_hash);
    const plan = color_solution_plan.compile(&selected);
    const input: [9]f32 = [0.5] ** 9;
    var output: [9]f32 = [9.0] ** 9;
    assert(color_solution_execute.render(plan, &selected, &cool,
        input[..], output[..], no_cancel, 0
    ) == 2 and output[0] == 9.0);
    var p3 = curves(0.75);
    p3.domain = rgb_gradation.display_p3_domain();
    var p3_hash: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&p3, p3_hash[0..], no_cancel, 0) == 0);
    const p3_request = request(p3_hash);
    const p3_plan = color_solution_plan.compile(&p3_request);
    assert(p3_plan.valid);
    assert(color_solution_execute.render(p3_plan, &p3_request, &p3,
        input[..], output[..], no_cancel, 0
    ) == 2 and output[0] == 9.0);
    selected.source_sha256 = hash(8);
    assert(color_solution_execute.render(plan, &selected, &warm,
        input[..], output[..], no_cancel, 0
    ) == 1 and output[0] == 9.0);
    selected.source_sha256 = hash(1);
    selected.initial_domain = color_solution_plan.SCENE_LINEAR_REC2020_D65;
    assert(color_solution_execute.render(plan, &selected, &warm,
        input[..], output[..], no_cancel, 0
    ) == 1 and output[0] == 9.0);
}

test "scene route converts neutral and saturated patches then grades view channels" {
    const warm = curves(0.75);
    const cool = curves(0.25);
    var warm_hash: [32]u8 = [0] ** 32;
    var cool_hash: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&warm, warm_hash[0..], no_cancel, 0) == 0);
    assert(rgb_gradation.digest(&cool, cool_hash[0..], no_cancel, 0) == 0);
    const warm_request = scene_request(warm_hash, 2, 2);
    const cool_request = scene_request(cool_hash, 2, 2);
    const warm_plan = color_solution_plan.compile(&warm_request);
    const cool_plan = color_solution_plan.compile(&cool_request);
    assert(warm_plan.valid and cool_plan.valid);
    const input: [12]f32 = [
        0.0, 0.0, 0.0, 0.5, 0.5, 0.5,
        1.0, 0.0, 0.0, 0.0, 0.0, 1.0
    ];
    const frame: color_solution_execute.SceneFrame = {
        version: 1,
        domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        width: 2,
        height: 2,
        samples: input[..]
    };
    var linear: [12]f32 = [9.0] ** 12;
    var clipped: [12]f32 = [9.0] ** 12;
    var encoded: [12]f32 = [9.0] ** 12;
    var warm_output: [12]f32 = [9.0] ** 12;
    var cool_output: [12]f32 = [9.0] ** 12;
    var replay: [12]f32 = [9.0] ** 12;
    assert(color_solution_execute.render_scene(warm_plan, &warm_request, &warm,
        &frame, linear[..], clipped[..], encoded[..], warm_output[..], no_cancel, 0
    ) == 0);
    assert(encoded[3] > 0.7353 and encoded[3] < 0.7354);
    assert(warm_output[0] == 0.0 and warm_output[1] == 0.0
        and warm_output[2] == 0.0
    );
    assert(warm_output[6] == 1.0 and warm_output[7] == 0.0
        and warm_output[8] == 0.0
    );
    assert(color_solution_execute.render_scene(cool_plan, &cool_request, &cool,
        &frame, linear[..], clipped[..], encoded[..], cool_output[..], no_cancel, 0
    ) == 0);
    assert(color_solution_execute.render_scene(warm_plan, &warm_request, &warm,
        &frame, linear[..], clipped[..], encoded[..], replay[..], no_cancel, 0
    ) == 0);
    assert(warm_output == replay and warm_output != cool_output);
    assert(warm_output[3] > cool_output[3]
        and warm_output[4] == cool_output[4]
        and warm_output[5] == cool_output[5]
    );
}

test "scene route rejects stale profile conversion and asset before final output" {
    const warm = curves(0.75);
    const cool = curves(0.25);
    var warm_hash: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&warm, warm_hash[0..], no_cancel, 0) == 0);
    var selected = scene_request(warm_hash, 1, 1);
    const plan = color_solution_plan.compile(&selected);
    assert(plan.valid);
    const input: [3]f32 = [0.5, 0.5, 0.5];
    var frame: color_solution_execute.SceneFrame = {
        version: 1,
        domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        width: 1,
        height: 1,
        samples: input[..]
    };
    var linear: [3]f32 = [9.0] ** 3;
    var clipped: [3]f32 = [9.0] ** 3;
    var encoded: [3]f32 = [9.0] ** 3;
    var output: [3]f32 = [9.0] ** 3;
    assert(color_solution_execute.render_scene(plan, &selected, &cool,
            &frame, linear[..], clipped[..], encoded[..], output[..], no_cancel, 0
        ) == 2
        and output[0] == 9.0
    );
    selected.source_profile_sha256 = hash(24);
    assert(color_solution_execute.render_scene(plan, &selected, &warm,
            &frame, linear[..], clipped[..], encoded[..], output[..], no_cancel, 0
        ) == 1
        and output[0] == 9.0
    );
    selected.source_profile_sha256 = hash(22);
    frame.domain = color_solution_plan.CAMERA_LINEAR;
    assert(color_solution_execute.render_scene(plan, &selected, &warm,
            &frame, linear[..], clipped[..], encoded[..], output[..], no_cancel, 0
        ) == 1
        and output[0] == 9.0
    );
    frame.domain = color_solution_plan.SCENE_LINEAR_REC2020_D65;
    selected.initial_domain = color_solution_plan.CAMERA_LINEAR;
    assert(color_solution_execute.render_scene(plan, &selected, &warm,
            &frame, linear[..], clipped[..], encoded[..], output[..], no_cancel, 0
        ) == 1
        and output[0] == 9.0
    );
    selected.initial_domain = color_solution_plan.SCENE_LINEAR_REC2020_D65;
    var conversion = selected.operations[0];
    conversion.algorithm_version = 2;
    selected.operations[0] = conversion;
    assert(color_solution_execute.render_scene(plan, &selected, &warm,
            &frame, linear[..], clipped[..], encoded[..], output[..], no_cancel, 0
        ) == 1
        and output[0] == 9.0
    );
}

test "same scene sample gives identical f32 output at two extents" {
    const asset = curves(0.75);
    var digest: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&asset, digest[0..], no_cancel, 0) == 0);
    const small_request = scene_request(digest, 1, 1);
    const large_request = scene_request(digest, 2, 2);
    const small_plan = color_solution_plan.compile(&small_request);
    const large_plan = color_solution_plan.compile(&large_request);
    const small_input: [3]f32 = [0.5, 0.5, 0.5];
    const large_input: [12]f32 = [0.5] ** 12;
    const small_frame: color_solution_execute.SceneFrame = {
        version: 1,
        domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        width: 1,
        height: 1,
        samples: small_input[..]
    };
    const large_frame: color_solution_execute.SceneFrame = {
        version: 1,
        domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        width: 2,
        height: 2,
        samples: large_input[..]
    };
    var small_linear: [3]f32 = [0.0] ** 3;
    var small_clipped: [3]f32 = [0.0] ** 3;
    var small_encoded: [3]f32 = [0.0] ** 3;
    var small_output: [3]f32 = [0.0] ** 3;
    var large_linear: [12]f32 = [0.0] ** 12;
    var large_clipped: [12]f32 = [0.0] ** 12;
    var large_encoded: [12]f32 = [0.0] ** 12;
    var large_output: [12]f32 = [0.0] ** 12;
    assert(color_solution_execute.render_scene(small_plan, &small_request, &asset,
        &small_frame, small_linear[..], small_clipped[..], small_encoded[..],
        small_output[..], no_cancel, 0
    ) == 0);
    assert(color_solution_execute.render_scene(large_plan, &large_request, &asset,
        &large_frame, large_linear[..], large_clipped[..], large_encoded[..],
        large_output[..], no_cancel, 0
    ) == 0);
    assert(small_output[0] == large_output[0]
        and small_output[1] == large_output[1]
        and small_output[2] == large_output[2]
    );
}

test "caller chroma map composes before view conversion with pinned domain" {
    const chroma = chroma_asset(chroma_map.REC2020_D65);
    const gradation = curves(0.75);
    var chroma_hash: [32]u8 = [0] ** 32;
    var gradation_hash: [32]u8 = [0] ** 32;
    assert(chroma_map.digest(&chroma, chroma_hash[0..], no_cancel, 0) == 0);
    assert(rgb_gradation.digest(&gradation, gradation_hash[0..], no_cancel, 0) == 0);
    const selected = chroma_request(chroma_hash, gradation_hash);
    const plan = color_solution_plan.compile(&selected);
    assert(plan.valid and plan.count == 3);
    const input: [3]f32 = [0.8, 0.2, 0.2];
    const frame: color_solution_execute.SceneFrame = {
        version: 1,
        domain: color_solution_plan.SCENE_LINEAR_REC2020_D65,
        source_sha256: hash(21),
        source_profile_sha256: hash(22),
        width: 1,
        height: 1,
        samples: input[..]
    };
    var mapped: [3]f32 = [9.0] ** 3;
    var linear: [3]f32 = [9.0] ** 3;
    var clipped: [3]f32 = [9.0] ** 3;
    var encoded: [3]f32 = [9.0] ** 3;
    var output: [3]f32 = [9.0] ** 3;
    assert(color_solution_execute.render_scene_chroma(plan, &selected,
        &chroma, &gradation, &frame, mapped[..], linear[..], clipped[..],
        encoded[..], output[..], no_cancel, 0
    ) == 0);
    assert(mapped[0] > 0.8466 and mapped[0] < 0.8468);
    assert(output[0] >= 0.0 and output[0] <= 1.0);
    var changed = chroma_asset(chroma_map.LINEAR_SRGB_D65);
    var wrong_hash: [32]u8 = [0] ** 32;
    assert(chroma_map.digest(&changed, wrong_hash[0..], no_cancel, 0) == 0);
    const wrong_request = chroma_request(wrong_hash, gradation_hash);
    const wrong_plan = color_solution_plan.compile(&wrong_request);
    output[0] = 9.0;
    assert(color_solution_execute.render_scene_chroma(wrong_plan, &wrong_request,
        &changed, &gradation, &frame, mapped[..], linear[..], clipped[..],
        encoded[..], output[..], no_cancel, 0
    ) == 2 and output[0] == 9.0);
    changed = chroma_asset(chroma_map.REC2020_D65);
    changed.strength = 0.5;
    assert(color_solution_execute.render_scene_chroma(plan, &selected,
        &changed, &gradation, &frame, mapped[..], linear[..], clipped[..],
        encoded[..], output[..], no_cancel, 0
    ) == 2 and output[0] == 9.0);
}
