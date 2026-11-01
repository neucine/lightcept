import .engine.pipeline.parameter_contract;

test "fused plan parameter rows follow compiler order" {
    const rows = parameter_contract.rows(1);
    assert(rows.len() == 5);
    assert(rows[0].stage == "exposure");
    assert(rows[0].name == "ev");
    assert(rows[0].minimum < 0.0);
    assert(rows[0].neutral == 0.0);
    assert(rows[1].name == "red_gain");
    assert(rows[2].name == "green_gain");
    assert(rows[3].name == "blue_gain");
    assert(rows[4].stage == "linear_chroma");
    assert(rows[4].name == "factor");
}

test "contrast plan inserts slope before chroma" {
    const rows = parameter_contract.rows(2);
    assert(rows.len() == 6);
    assert(rows[4].stage == "contrast");
    assert(rows[4].name == "slope");
    assert(rows[4].neutral == 1.0);
    assert(rows[5].stage == "linear_chroma");
    assert(rows[5].index == 5);
}

test "split output plan retains working parameter order" {
    const fused = parameter_contract.rows(1);
    const split = parameter_contract.rows(3);
    assert(split.len() == fused.len());
    var index: usize = 0;
    while index < split.len() {
        assert(split[index].name == fused[index].name);
        assert(split[index].stage_id == fused[index].stage_id);
        index = index + 1;
    }
}
