import .engine.core.core;
import .engine.analysis.clip_map;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "clip map preserves channel identity across a small photographic strip" {
    const input: [12]f32 = [0.18, 0.18, 0.18, 1.0, 0.4, 0.3,
        0.3, 1.1, 1.2, -0.1, 1.0, 0.2
    ];
    var output: [4]u8 = [9, 9, 9, 9];
    assert(clip_map.build(input[0..], 2, 2, 1.0, output[0..], no_cancel, 0) == 0);
    assert(output[0] == 0 and output[1] == 1 and output[2] == 6 and output[3] == 2);
}

test "clip map rejects shape and nonfinite samples before writing" {
    const input: [6]f32 = [0.2, 0.2, 0.2, 1.0, 1.0, 1.0];
    var output: [2]u8 = [9, 9];
    assert(clip_map.build(input[0..], 2, 1, 0.4, output[0..], no_cancel, 0) == 1);
    assert(clip_map.build(input[0..], 3, 1, 1.0, output[0..], no_cancel, 0) == 2);
    const infinity = core.positive_infinity32();
    const nonfinite: [6]f32 = [0.2, 0.2, 0.2, infinity, 1.0, 1.0];
    assert(clip_map.build(nonfinite[0..], 2, 1, 1.0, output[0..], no_cancel, 0) == 3);
    const out_of_domain: [6]f32 = [0.2, 0.2, 0.2, 8.1, 1.0, 1.0];
    assert(clip_map.build(out_of_domain[0..], 2, 1, 1.0,
        output[0..], no_cancel, 0
    ) == 3);
    assert(output[0] == 9 and output[1] == 9);
    assert(clip_map.build(input[0..], 2, 1, 1.0, output[0..], cancel, 0) == 7);
    assert(output[0] == 9 and output[1] == 9);
}
