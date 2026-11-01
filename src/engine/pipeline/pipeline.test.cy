import .engine.pipeline.pipeline;

test "the fixed working plan validates its controls" {
    assert(pipeline.valid_working_plan_parameters(0.0, 1.0, 1.0, 1.0, 1.0));
    assert(not pipeline.valid_working_plan_parameters(0.0, 1.0, 1.0, 1.0, 2.5));
    assert(not pipeline.valid_working_plan_parameters(17.0, 1.0, 1.0, 1.0, 1.0));
    assert(pipeline.compose_exposure(0.5, -0.25) == 0.25);
}
