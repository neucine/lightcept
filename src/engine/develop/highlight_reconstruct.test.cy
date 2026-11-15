import .engine.core.core;
import .engine.develop.highlight_reconstruct;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): highlight_reconstruct.HighlightAsset {
    return {
        version: 1,
        cfa: [0, 1, 1, 2],
        clip_threshold: 0.99,
        maximum_value: 2.0,
        maximum_change: 0.5
    };
}

test "RAW highlight reconstruct extends a supported same-phase slope" {
    const input: [5]f32 = [0.7, 0.3, 0.9, 0.3, 1.0];
    const clip: [5]u8 = [0, 0, 0, 0, 1];
    var output: [5]f32 = [9.0] ** 5;
    assert(highlight_reconstruct.apply(input[0..], clip[0..], 5, 1,
        settings(), output[0..], no_cancel, 0
    ) == 0);
    assert(output[4] > 1.099 and output[4] < 1.101);
    assert(output[0] == input[0] and output[2] == input[2]);
    var vertical: [5]f32 = [9.0] ** 5;
    assert(highlight_reconstruct.apply(input[0..], clip[0..], 1, 5,
        settings(), vertical[0..], no_cancel, 0
    ) == 0);
    assert(vertical[4] > 1.099 and vertical[4] < 1.101);
}

test "RAW highlight reconstruct leaves unsupported saturation and caps change" {
    const plateau: [5]f32 = [1.0] ** 5;
    const clipped: [5]u8 = [1] ** 5;
    var output: [5]f32 = [9.0] ** 5;
    assert(highlight_reconstruct.apply(plateau[0..], clipped[0..], 5, 1,
        settings(), output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 1.0 and output[4] == 1.0);
    const slope: [5]f32 = [0.1, 0.2, 0.9, 0.2, 1.0];
    const clip: [5]u8 = [0, 0, 0, 0, 1];
    var limited = settings();
    limited.maximum_change = 0.05;
    assert(highlight_reconstruct.apply(slope[0..], clip[0..], 5, 1,
        limited, output[0..], no_cancel, 0
    ) == 0);
    assert(output[4] > 1.049 and output[4] < 1.051);
}

test "RAW highlight reconstruct validates evidence input and cancellation" {
    const input: [1]f32 = [1.0];
    const clip: [1]u8 = [1];
    var output: [1]f32 = [9.0];
    var bad = settings();
    bad.cfa = [0, 1, 2, 1];
    assert(highlight_reconstruct.apply(input[0..], clip[0..], 1, 1,
        bad, output[0..], no_cancel, 0
    ) == 1);
    assert(highlight_reconstruct.apply(input[0..], clip[0..], 2, 1,
        settings(), output[0..], no_cancel, 0
    ) == 2);
    const infinity = core.positive_infinity32();
    const nonfinite: [1]f32 = [infinity];
    assert(highlight_reconstruct.apply(nonfinite[0..], clip[0..], 1, 1,
        settings(), output[0..], no_cancel, 0
    ) == 3);
    const wrong: [1]u8 = [0];
    assert(highlight_reconstruct.apply(input[0..], wrong[0..], 1, 1,
        settings(), output[0..], no_cancel, 0
    ) == 4);
    assert(highlight_reconstruct.apply(input[0..], clip[0..], 1, 1,
        settings(), output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
