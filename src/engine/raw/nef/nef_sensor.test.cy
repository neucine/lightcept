// Analytical vectors for the headless Nikon sensor stage. The crop starts at
// odd stored coordinates, so all four black-level positions are exercised.
import .engine.raw.nef.nef_sensor;

extern c("lc_cyna_img_v1_normalize_nef_sensor") fn normalize(
    input: *const c_ushort, input_len: c_size_t,
    stored_width: c_size_t, stored_height: c_size_t,
    crop_left: c_size_t, crop_top: c_size_t,
    crop_width: c_size_t, crop_height: c_size_t,
    black00: c_uint, black01: c_uint, black10: c_uint, black11: c_uint,
    white: c_uint,
    output: *c_float, output_len: c_size_t,
    cancelled: c fn (*const c_uchar): c_int, cancel_context: *const c_uchar
): c_int;

fn no_cancel(context: *const c_uchar): c_int {
    const ignored = context;
    return 0;
}

fn cancel(context: *const c_uchar): c_int {
    const ignored = context;
    return 1;
}

test "NEF cropped CFA follows the sensor crop origin" {
    const rggb: u32 = 0x02010100;
    assert(nef_sensor.cropped_cfa(rggb, 0, 0) == rggb);
    assert(nef_sensor.cropped_cfa(rggb, 1, 0) == 0x01020001);
    assert(nef_sensor.cropped_cfa(rggb, 0, 1) == 0x01000201);
    assert(nef_sensor.cropped_cfa(rggb, 1, 1) == 0x00010102);
}

test "NEF normalization uses stored CFA parity and preserves signed headroom" {
    // Crop x=1..2, y=1..2. Black values at these coordinates are 40, 30,
    // 20, 10 respectively; the output order is row major.
    const samples: [12]u16 = [0, 0, 0, 0, 30, 110, 0, 10, 130, 0, 0, 0];
    var output: [4]f32 = [9.0] ** 4;
    const status = normalize(samples[0..].ptr as! *const c_ushort, 12, 3, 4,
        1, 1, 2, 2, 10, 20, 30, 40, 100,
        output[0..].ptr as! *c_float, 4, no_cancel, 0 as! *const c_uchar
    );
    assert(status == 0);
    assert(output[0] == (-10 as f32) / (60 as f32));
    assert(output[1] == (80 as f32) / (70 as f32));
    assert(output[2] == (-10 as f32) / (80 as f32));
    assert(output[3] == (120 as f32) / (90 as f32));
}

test "NEF normalization rejects invalid geometry and cancellation before writing" {
    const samples: [4]u16 = [20, 20, 20, 20];
    var output: [4]f32 = [9.0] ** 4;
    const input = samples[0..].ptr as! *const c_ushort;
    const result = output[0..].ptr as! *c_float;
    assert(normalize(input, 4, 2, 2, 1, 0, 2, 2, 10, 10, 10, 10, 100,
        result, 4, no_cancel, 0 as! *const c_uchar
    ) == 4);
    assert(normalize(input, 4, 2, 2, 0, 0, 2, 2, 10, 10, 10, 10, 100,
        result, 4, cancel, 0 as! *const c_uchar
    ) == 7);
    assert(normalize(0 as! *const c_ushort, 4, 2, 2, 0, 0, 2, 2, 10, 10, 10, 10, 100,
        result, 4, no_cancel, 0 as! *const c_uchar
    ) == 4);
    assert(normalize(input, 4, 2, 2, 0, 0, 2, 2, 10, 10, 10, 10, 100,
        0 as! *c_float, 4, no_cancel, 0 as! *const c_uchar
    ) == 4);
    assert(output[0] == 9.0 and output[3] == 9.0);
}
