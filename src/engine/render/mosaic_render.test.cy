import .engine.render.mosaic_render;
import .engine.color.nef.nikon_z6_ii_profile;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

test "NEF highlight reconstruction neutralizes a clipped sky after baked gains" {
    const red_gain: f64 = 1.837890625;
    const blue_gain: f64 = 1.345703125;
    var matrix: [9]f64 = [0.0] ** 9;
    if nikon_z6_ii_profile.camera_to_xyz_d50(red_gain, blue_gain) is values {
        matrix = values;
    } else {
        assert(false);
    }
    const neutral: [3]f64 = [1.0 / red_gain, 1.0, 1.0 / blue_gain];
    const cfa: [4]u32 = [0, 1, 1, 2];
    var normalized: [16]f32 = [0.0] ** 16;
    var index: usize = 0;
    while index < 16 {
        normalized[index] = 1.075;
        index = index + 1;
    }
    var repaired: [48]f64 = [0.0] ** 48;
    var unrepaired: [48]f64 = [0.0] ** 48;
    assert(mosaic_render.prepare_oriented_working_preview_highlight(
        normalized[0..], 4, 4, cfa, matrix, neutral, repaired[0..], 4, 4,
        1, 3, no_cancel, 0
    ) == 0);
    assert(mosaic_render.prepare_oriented_working_preview(
        normalized[0..], 4, 4, cfa, matrix, unrepaired[0..], 4, 4,
        1, no_cancel, 0
    ) == 0);
    var pixel: usize = 0;
    while pixel < 16 {
        const at = pixel * 3;
        assert(repaired[at] > 1.0);
        const green_delta = repaired[at + 1] - repaired[at];
        const blue_delta = repaired[at + 2] - repaired[at];
        assert(green_delta > -0.000001 and green_delta < 0.000001);
        assert(blue_delta > -0.000001 and blue_delta < 0.000001);
        pixel = pixel + 1;
    }
    assert(unrepaired[0] > unrepaired[1] * 1.5);
}
