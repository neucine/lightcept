import .engine.color.srgb_clip;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "sRGB clip confines signed linear primary values" {
    const input: [6]f32 = [1.5, -0.2, 0.123, 0.0, 1.0, 0.5];
    var output: [6]f32 = [9.0] ** 6;
    assert(srgb_clip.apply(input[0..], 2, 1,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 1.0 and output[1] == 0.0);
    assert(output[2] == input[2] and output[5] == input[5]);
    assert(srgb_clip.channel(-0.2) == output_color.clip_linear_srgb(-0.2));
    assert(srgb_clip.channel(0.5) == output_color.clip_linear_srgb(0.5));
}

test "sRGB clip rejects shape domain and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0] ** 3;
    assert(srgb_clip.apply(input[0..], 2, 1,
        output[0..], no_cancel, 0
    ) == 1);
    const invalid: [3]f32 = [17.0, 0.3, 0.4];
    assert(srgb_clip.apply(invalid[0..], 1, 1,
        output[0..], no_cancel, 0
    ) == 2);
    assert(srgb_clip.apply(input[0..], 1, 1,
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0);
}
