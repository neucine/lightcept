import .engine.core.core;
import .engine.develop.grain;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "grain is deterministic by seed and source coordinate" {
    const asset: grain.GrainAsset = {
        version: 1,
        seed: 123,
        amplitude: 0.05
    };
    const same = grain.offset(asset, 5, 7);
    assert(same == grain.offset(asset, 5, 7));
    assert(same >= -0.05 and same <= 0.05);
    const other: grain.GrainAsset = {
        version: 1,
        seed: 124,
        amplitude: 0.05
    };
    assert(same != grain.offset(other, 5, 7));
    assert(same != grain.offset(asset, 6, 7));
}

test "grain preserves disabled identity and monochrome channel differences" {
    const input: [12]f32 = [-0.1, 0.2, 1.5, 0.18, 0.18, 0.18,
        0.4, 0.3, 0.2, 0.9, 0.8, 0.7
    ];
    var output: [12]f32 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    ];
    const neutral: grain.GrainAsset = {
        version: 1,
        seed: 42,
        amplitude: 0.0
    };
    assert(grain.apply(input[0..], 2, 2, neutral, output[0..], no_cancel, 0) == 0);
    assert(output[0] == input[0] and output[2] == input[2] and output[11] == input[11]);
    const active: grain.GrainAsset = {
        version: 1,
        seed: 42,
        amplitude: 0.05
    };
    assert(grain.apply(input[0..], 2, 2, active, output[0..], no_cancel, 0) == 0);
    assert(output[0] != input[0] and output[3] != input[3]);
    const difference = (output[0] as f64 - output[1] as f64)
    - (input[0] as f64 - input[1] as f64);
    assert(difference > -0.0000001 and difference < 0.0000001);
}

test "grain rejects malformed input and cancellation before writing" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    const invalid: grain.GrainAsset = {
        version: 1,
        seed: 0,
        amplitude: 0.11
    };
    const valid: grain.GrainAsset = {
        version: 1,
        seed: 0,
        amplitude: 0.05
    };
    assert(grain.apply(input[0..], 1, 1, invalid, output[0..], no_cancel, 0) == 1);
    assert(grain.apply(input[0..], 2, 1, valid, output[0..], no_cancel, 0) == 2);
    const infinity = core.positive_infinity32();
    const bad: [3]f32 = [infinity, 0.3, 0.4];
    assert(grain.apply(bad[0..], 1, 1, valid, output[0..], no_cancel, 0) == 3);
    assert(grain.apply(input[0..], 1, 1, valid, output[0..], cancel, 0) == 7);
    assert(output[0] == 9.0 and output[1] == 9.0 and output[2] == 9.0);
}
