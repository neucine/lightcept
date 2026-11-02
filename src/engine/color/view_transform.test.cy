import .engine.color.view_transform;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "sRGB reference view retains fixed display identity and output parity" {
    const reference = view_transform.srgb_reference();
    assert(view_transform.valid(reference));
    assert(reference.white_nits == 80.0 and reference.black_nits == 0.2);
    const input: [12]f32 = [0.0, 0.0, 0.0, 0.18, 0.18, 0.18,
        1.0, 0.0, 0.0, -0.1, 0.4, 2.0
    ];
    var output: [12]f32 = [9.0] ** 12;
    const report = view_transform.apply(input[0..], 2, 2,
        reference, output[0..], no_cancel, 0
    );
    assert(report.status == 0 and report.version == 1 and report.pixels == 4);
    assert(report.clipped_pixels == 2);
    assert(output[3] > 0.461 and output[3] < 0.462);
    assert(output[6] == 1.0 and output[7] == 0.0 and output[8] == 0.0);
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

test "view transform validates reference shape samples and cancellation" {
    const input: [3]f32 = [0.2, 0.3, 0.4];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    var reference = view_transform.srgb_reference();
    reference.white_nits = 100.0;
    assert(view_transform.apply(input[0..], 1, 1,
        reference, output[0..], no_cancel, 0
    ).status == 1);
    reference = view_transform.srgb_reference();
    assert(view_transform.apply(input[0..], 0, 1,
        reference, output[0..], no_cancel, 0
    ).status == 2);
    const bad: [3]f32 = [9.0, 0.3, 0.4];
    assert(view_transform.apply(bad[0..], 1, 1,
        reference, output[0..], no_cancel, 0
    ).status == 3);
    assert(view_transform.apply(input[0..], 1, 1,
        reference, output[0..], cancel, 0
    ).status == 7);
    assert(output[0] == 9.0);
}
