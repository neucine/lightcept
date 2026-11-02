import .engine.render.output_transform;
import .engine.color.output_color;
import .engine.render.render;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "fused output transform matches accepted sRGB quantization on a scene strip" {
    const input: [12]f32 = [0.0, 0.0, 0.0, 0.18, 0.18, 0.18,
        1.0, 0.0, 0.0, -0.1, 0.4, 2.0
    ];
    var rgba: [16]u8 = [0] ** 16;
    var rgb16: [12]u16 = [0] ** 12;
    assert(output_transform.rgba8(input[0..], 2, 2, rgba[0..], no_cancel, 0) == 0);
    assert(output_transform.rgb16(input[0..], 2, 2, rgb16[0..], no_cancel, 0) == 0);
    var pixel: usize = 0;
    while pixel < 4 {
        var channel: usize = 0;
        while channel < 3 {
            const encoded = output_color.encode_channel(input[pixel * 3] as f64,
                input[pixel * 3 + 1] as f64, input[pixel * 3 + 2] as f64,
                channel as i32
            );
            assert(rgba[pixel * 4 + channel] == render.quantize(encoded));
            assert(rgb16[pixel * 3 + channel] == render.quantize16(encoded));
            channel = channel + 1;
        }
        assert(rgba[pixel * 4 + 3] == 255);
        pixel = pixel + 1;
    }
    assert(rgba[0] == 0 and rgba[1] == 0 and rgba[2] == 0);
    assert(rgb16[0] == 0 and rgb16[1] == 0 and rgb16[2] == 0);
    assert(rgba[4] == 118 and rgba[5] == 118 and rgba[6] == 118);
    assert(rgb16[3] == 30235 and rgb16[4] == 30235 and rgb16[5] == 30235);
    assert(rgba[8] == 255 and rgba[9] == 0 and rgba[10] == 0);
    assert(rgb16[6] == 65535 and rgb16[7] == 0 and rgb16[8] == 0);
}

test "fused output transform validates geometry inputs and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var rgba: [4]u8 = [9] ** 4;
    var rgb16: [3]u16 = [9] ** 3;
    assert(output_transform.rgba8(input[0..], 0, 1, rgba[0..], no_cancel, 0) == 1);
    assert(output_transform.rgb16(input[0..], 2, 1, rgb16[0..], no_cancel, 0) == 1);
    const invalid: [3]f32 = [9.0, 0.3, 0.4];
    assert(output_transform.rgba8(invalid[0..], 1, 1, rgba[0..], no_cancel, 0) == 2);
    assert(output_transform.rgb16(invalid[0..], 1, 1, rgb16[0..], no_cancel, 0) == 2);
    assert(output_transform.rgba8(input[0..], 1, 1, rgba[0..], cancel, 0) == 7);
    assert(output_transform.rgb16(input[0..], 1, 1, rgb16[0..], cancel, 0) == 7);
    assert(rgba[0] == 9 and rgb16[0] == 9);
}
