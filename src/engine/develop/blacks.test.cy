import .engine.develop.blacks;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(offset: f64): blacks.BlacksAsset {
    return {
        version: 1,
        offset: offset
    };
}

test "black toe decays to the middle-gray pivot" {
    assert(blacks.toe_weight(-0.1) == 1.0);
    assert(blacks.toe_weight(0.0) == 1.0);
    assert(blacks.toe_weight(0.09) == 0.25);
    assert(blacks.toe_weight(0.18) == 0.0);
    assert(blacks.toe_weight(2.0) == 0.0);
    const input: [12]f32 = [0.0, 0.0, 0.0,
        0.09, 0.09, 0.09,
        0.18, 0.18, 0.18,
        1.5, 1.5, 1.5
    ];
    var output: [12]f32 = [9.0] ** 12;
    assert(blacks.apply(input[0..], 4, 1, settings(0.1),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] < -0.099 and output[0] > -0.101);
    assert(output[3] > 0.064 and output[3] < 0.066);
    assert(output[6] == input[6] and output[9] == input[9]);
}

test "black toe preserves chroma differences and neutral identity" {
    const adjusted = blacks.adjust(0.2, 0.1, 0.0, settings(0.08));
    assert(adjusted[0] - adjusted[1] > 0.099999
        and adjusted[0] - adjusted[1] < 0.100001
    );
    assert(adjusted[1] - adjusted[2] > 0.099999
        and adjusted[1] - adjusted[2] < 0.100001
    );
    const input: [3]f32 = [-0.2, 0.2, 1.5];
    var output: [3]f32 = [9.0] ** 3;
    assert(blacks.apply(input[0..], 1, 1, settings(0.0),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[2] == input[2]);
}

test "black toe rejects asset shape input and cancellation" {
    const input: [3]f32 = [0.2, 0.2, 0.2];
    var output: [3]f32 = [9.0] ** 3;
    assert(blacks.apply(input[0..], 1, 1, settings(0.126),
        output[0..], no_cancel, 0
    ) == 1);
    assert(blacks.apply(input[0..], 2, 1, settings(0.1),
        output[0..], no_cancel, 0
    ) == 2);
    const invalid: [3]f32 = [9.0, 0.2, 0.2];
    assert(blacks.apply(invalid[0..], 1, 1, settings(0.1),
        output[0..], no_cancel, 0
    ) == 3);
    assert(blacks.apply(input[0..], 1, 1, settings(0.1),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
