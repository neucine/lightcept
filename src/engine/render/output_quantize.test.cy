import .engine.render.output_quantize;
import .engine.render.render;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "encoded sRGB quantizes endpoints midpoint and small signal" {
    const input: [6]f32 = [0.0, 0.5, 1.0, 0.1, 0.25, 0.75];
    var bytes: [6]u8 = [0] ** 6;
    var words: [6]u16 = [0] ** 6;
    assert(output_quantize.apply8(input[0..], 2, 1,
        bytes[0..], no_cancel, 0
    ) == 0);
    assert(output_quantize.apply16(input[0..], 2, 1,
        words[0..], no_cancel, 0
    ) == 0);
    assert(bytes[0] == 0 and bytes[1] == 128 and bytes[2] == 255);
    assert(words[0] == 0 and words[1] == 32768 and words[2] == 65535);
    assert(bytes[3] == render.quantize(input[3] as f64));
    assert(words[3] == render.quantize16(input[3] as f64));
}

test "quantization validates shape domain and cancellation" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var bytes: [3]u8 = [9] ** 3;
    var words: [3]u16 = [9] ** 3;
    assert(output_quantize.apply8(input[0..], 2, 1,
        bytes[0..], no_cancel, 0
    ) == 1);
    const invalid: [3]f32 = [1.1, 0.2, 0.3];
    assert(output_quantize.apply8(invalid[0..], 1, 1,
        bytes[0..], no_cancel, 0
    ) == 2);
    assert(output_quantize.apply16(invalid[0..], 1, 1,
        words[0..], no_cancel, 0
    ) == 2);
    assert(output_quantize.apply8(input[0..], 1, 1,
        bytes[0..], cancel, 0
    ) == 7);
    assert(output_quantize.apply16(input[0..], 1, 1,
        words[0..], cancel, 0
    ) == 7);
    assert(bytes[0] == 9 and words[0] == 9);
}
