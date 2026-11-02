import .engine.color.gamut_map;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn policy(intent: u32): gamut_map.MapPolicy {
    return {
        version: 1,
        destination: gamut_map.destination_srgb2014,
        intent: intent
    };
}

test "gamut map colorimetric branch matches the fixed sRGB output encoder" {
    const input: [12]f32 = [0.18, 0.18, 0.18, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, -0.1, 0.3, 0.5
    ];
    var output: [12]f32 = [9.0] ** 12;
    const report = gamut_map.apply(input[0..], 2, 2,
        policy(gamut_map.relative_colorimetric), output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.pixels == 4);
    assert(report.outside_pixels >= 2 and report.outside_pixels <= 3);
    var pixel: usize = 0;
    while pixel < 4 {
        var channel: usize = 0;
        while channel < 3 {
            const expected = output_color.encode_channel(input[pixel * 3] as f64,
                input[pixel * 3 + 1] as f64, input[pixel * 3 + 2] as f64,
                channel as i32
            );
            const actual = output[pixel * 3 + channel] as f64;
            assert(actual > expected - 0.000001 and actual < expected + 0.000001);
            channel = channel + 1;
        }
        pixel = pixel + 1;
    }
}

test "gamut map perceptual branch compresses chroma toward destination neutral" {
    const source: [3]f64 = [1.2, 0.1, -0.2];
    const mapped = gamut_map.map_linear_checked(source, gamut_map.perceptual);
    assert(mapped.status == 0);
    const y = 0.2126 * source[0] + 0.7152 * source[1] + 0.0722 * source[2];
    const mapped_y = 0.2126 * mapped.red + 0.7152 * mapped.green + 0.0722 * mapped.blue;
    assert(mapped.red >= 0.0 and mapped.red <= 1.0);
    assert(mapped.green >= 0.0 and mapped.green <= 1.0);
    assert(mapped.blue >= 0.0 and mapped.blue <= 1.0);
    assert(mapped.red > mapped.green and mapped.green > mapped.blue);
    assert(mapped_y > y - 0.000001 and mapped_y < y + 0.000001);
    const in_gamut: [3]f64 = [0.7, 0.2, 0.1];
    const unchanged = gamut_map.map_linear_checked(in_gamut, gamut_map.perceptual);
    assert(unchanged.status == 0);
    assert(unchanged.red == in_gamut[0] and unchanged.green == in_gamut[1]);
    assert(gamut_map.map_linear_checked(source, 3).status == 1);
    assert(gamut_map.map_linear_checked([17.0, 0.0, 0.0], gamut_map.perceptual).status == 2);
}

test "perceptual gamut map changes an out-of-gamut photographic strip" {
    const input: [12]f32 = [0.18, 0.18, 0.18,
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0
    ];
    var output: [12]f32 = [9.0] ** 12;
    const report = gamut_map.apply(input[0..], 2, 2,
        policy(gamut_map.perceptual), output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.intent == gamut_map.perceptual);
    assert(report.outside_pixels == 3);
    assert(output[3] == 1.0 and output[4] > 0.0 and output[5] > 0.0);
    assert(output[0] > 0.46 and output[0] < 0.47);
    assert(output[9] >= 0.0 and output[9] <= 1.0);
}

test "gamut map rejects policy input and cancellation before valid output" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    assert(gamut_map.apply(input[0..], 1, 1, policy(3), output[0..], no_cancel, 0).status == 1);
    assert(gamut_map.apply(input[0..], 0, 1, policy(1), output[0..], no_cancel, 0).status == 2);
    const bad: [3]f32 = [9.0, 0.3, 0.4];
    assert(gamut_map.apply(bad[0..], 1, 1, policy(1), output[0..], no_cancel, 0).status == 3);
    assert(gamut_map.apply(input[0..], 1, 1, policy(1), output[0..], cancel, 0).status == 7);
    assert(output[0] == 9.0);
}
