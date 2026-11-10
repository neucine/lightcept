import .engine.render.working_rgb_render;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    const ignored = context;
    return true;
}

test "working RGB16 uses the preview color plan before quantization" {
    const working: [9]f64 = [0.03, 0.08, 0.15, 0.25, 0.35, 0.45, 0.7, 0.6, 0.5];
    var preview: [12]u8 = [0] ** 12;
    var export_rgb: [9]u16 = [0] ** 9;
    assert(working_rgb_render.render_working_rgba8_with_color(
        working[0..].ptr, 9, preview[0..].ptr, 12, 3, 1,
        0.0, 0.5, 1.15, -0.01, 0.2, -0.1, 0.15,
        10, -10, 20, 10, no_cancel, 0
    ) == 0);
    assert(working_rgb_render.render_working_rgb16_with_color(
        working[0..].ptr, 9, export_rgb[0..].ptr, 9, 3, 1,
        0.0, 0.5, 1.15, -0.01, 0.2, -0.1, 0.15,
        10, -10, 20, 10, no_cancel, 0
    ) == 0);
    var pixel: usize = 0;
    var has_extra_precision = false;
    while pixel < 3 {
        var channel: usize = 0;
        while channel < 3 {
            const coarse = preview[pixel * 4 + channel] as i32;
            const fine = (export_rgb[pixel * 3 + channel] / 257) as i32;
            assert(fine >= coarse - 1 and fine <= coarse + 1);
            if export_rgb[pixel * 3 + channel] % 257 != 0 {
                has_extra_precision = true;
            }
            channel = channel + 1;
        }
        pixel = pixel + 1;
    }
    assert(has_extra_precision);
}

test "working RGB16 rejects invalid controls and cancellation" {
    const working: [3]f64 = [0.1, 0.2, 0.3];
    var output: [3]u16 = [9] ** 3;
    assert(working_rgb_render.render_working_rgb16_with_color(
        working[0..].ptr, 3, output[0..].ptr, 3, 1, 1,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0, 101, no_cancel, 0
    ) != 0);
    assert(working_rgb_render.render_working_rgb16_with_color(
        working[0..].ptr, 3, output[0..].ptr, 3, 1, 1,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0, 0, cancel, 0
    ) == 7);
    assert(output[0] == 9 and output[2] == 9);
}

test "tiled RGB16 Detail follows the whole-frame preview across tile seams" {
    var working: [2340]f64 = [0.0] ** 2340;
    var preview: [3120]u8 = [0] ** 3120;
    var export_rgb: [2340]u16 = [0] ** 2340;
    var index: usize = 0;
    while index < 780 {
        const band = ((index / 3) % 7) as f64 / 70.0;
        working[index * 3] = 0.12 + band;
        working[index * 3 + 1] = 0.18 + band;
        working[index * 3 + 2] = 0.25 + band;
        index = index + 1;
    }
    assert(working_rgb_render.render_working_rgba8_with_detail(
        working[0..].ptr, 2340, preview[0..].ptr, 3120, 3, 260,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0, 0, 30, 40, no_cancel, 0
    ) == 0);
    assert(working_rgb_render.render_working_rgb16_with_detail(
        working[0..].ptr, 2340, export_rgb[0..].ptr, 2340, 3, 260,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0, 0, 30, 40, no_cancel, 0
    ) == 0);
    index = 0;
    while index < 780 {
        var channel: usize = 0;
        while channel < 3 {
            const coarse = preview[index * 4 + channel] as i32;
            const fine = (export_rgb[index * 3 + channel] / 257) as i32;
            assert(fine >= coarse - 1 and fine <= coarse + 1);
            channel = channel + 1;
        }
        index = index + 1;
    }
}
