import .engine.pipeline.color_solution_plan;

fn digest(value: u8): [32]u8 {
    var hash: [32]u8 = [0] ** 32;
    hash[0] = value;
    return hash;
}

fn operation(slot: u32, input: u32, output: u32, asset: u8, profile: u8): color_solution_plan.Operation {
    return {
        slot: slot,
        algorithm_version: 1,
        input_domain: input,
        output_domain: output,
        asset_sha256: digest(asset),
        source_profile_sha256: digest(profile)
    };
}

test "color solution accepts bounded scene and view route and pins replay" {
    const steps: [:]color_solution_plan.Operation = [
        operation(1, 1, 2, 10, 2), operation(2, 2, 2, 11, 0),
        operation(3, 2, 3, 12, 0), operation(4, 3, 4, 13, 0)
    ];
    var request: color_solution_plan.Request = {
        route_version: 1,
        source_sha256: digest(1),
        source_profile_sha256: digest(2),
        initial_domain: 1,
        branch_sha256: digest(3),
        width: 3,
        height: 2,
        max_pixels: 6,
        operations: steps
    };
    const plan = color_solution_plan.compile(&request);
    assert(plan.valid and plan.count == 4 and color_solution_plan.matches(plan, &request));
    request.branch_sha256 = digest(4);
    assert(not color_solution_plan.matches(plan, &request));
    request.branch_sha256 = digest(3);
    var changed = request.operations[1];
    changed.asset_sha256 = digest(15);
    request.operations[1] = changed;
    assert(not color_solution_plan.matches(plan, &request));
}

test "color solution rejects wrong domain order source and resource bound" {
    var steps: [:]color_solution_plan.Operation = [
        operation(1, 1, 2, 10, 2), operation(2, 2, 2, 11, 0),
        operation(4, 2, 4, 13, 0)
    ];
    var request: color_solution_plan.Request = {
        route_version: 1,
        source_sha256: digest(1),
        source_profile_sha256: digest(2),
        initial_domain: 1,
        branch_sha256: digest(3),
        width: 3,
        height: 2,
        max_pixels: 6,
        operations: steps
    };
    assert(color_solution_plan.compile(&request).valid);
    request.max_pixels = 5;
    assert(not color_solution_plan.compile(&request).valid);
    request.max_pixels = 6;
    var changed = request.operations[1];
    changed.input_domain = 3;
    request.operations[1] = changed;
    assert(not color_solution_plan.compile(&request).valid);
    changed.input_domain = 2;
    request.operations[1] = changed;
    changed.source_profile_sha256 = digest(9);
    request.operations[1] = changed;
    assert(not color_solution_plan.compile(&request).valid);
    changed.source_profile_sha256 = digest(0);
    request.operations[1] = changed;
    changed.slot = 4;
    request.operations[1] = changed;
    assert(not color_solution_plan.compile(&request).valid);
}
