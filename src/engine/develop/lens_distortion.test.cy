import .engine.core.core;
import .engine.develop.lens_distortion;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(): lens_distortion.LensAsset {
    return {
        version: 1,
        model_hash: 1,
        center_x_fraction: 0.5,
        center_y_fraction: 0.5,
        k1: 0.2,
        boundary_fill: [0.0, 0.0, 0.0]
    };
}

test "lens distortion identity and inverse point mapping" {
    const input: [12]f32 = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6,
        0.7, 0.8, 0.9, 1.0, 1.1, 1.2
    ];
    var output: [12]f32 = [9.0] ** 12;
    var neutral = settings();
    neutral.k1 = 0.0;
    assert(lens_distortion.apply(input[0..], 2, 2, neutral,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[11] == input[11]);
    const center = lens_distortion.map_source_point(5, 5, settings(), 2.0, 2.0);
    assert(center.inside and center.x == 2.0 and center.y == 2.0);
    const mapped = lens_distortion.map_source_point(5, 5, settings(), 3.0, 2.0);
    assert(mapped.inside and mapped.x > 3.0 and mapped.x < 3.3);
}

test "lens distortion resamples a radial gradient and fills outside" {
    var input: [75]f32 = [0.0] ** 75;
    var y: usize = 0;
    while y < 5 {
        var x: usize = 0;
        while x < 5 {
            const index = (y * 5 + x) * 3;
            input[index] = x as f32;
            input[index + 1] = y as f32;
            input[index + 2] = 0.5;
            x = x + 1;
        }
        y = y + 1;
    }
    var output: [75]f32 = [9.0] ** 75;
    assert(lens_distortion.apply(input[0..], 5, 5, settings(),
        output[0..], no_cancel, 0
    ) == 0);
    const index: usize = (2 * 5 + 3) * 3;
    assert(output[index] > 2.82 and output[index] < 2.83);
    assert(output[index + 1] == 2.0);
    var barrel = settings();
    barrel.k1 = -0.2;
    assert(lens_distortion.apply(input[0..], 5, 5, barrel,
        output[0..], no_cancel, 0
    ) == 0);
    const border: usize = (2 * 5 + 4) * 3;
    assert(output[border] == 0.0 and output[border + 1] == 0.0);
}

test "lens distortion rejects asset shape input and cancellation" {
    const input: [12]f32 = [0.2] ** 12;
    var output: [12]f32 = [9.0] ** 12;
    var bad = settings();
    bad.model_hash = 0;
    assert(lens_distortion.apply(input[0..], 2, 2, bad,
        output[0..], no_cancel, 0
    ) == 1);
    assert(lens_distortion.apply(input[0..], 2, 2, settings(),
        output[0..3], no_cancel, 0
    ) == 2);
    const infinity = core.positive_infinity32();
    var nonfinite: [12]f32 = [0.2] ** 12;
    nonfinite[0] = infinity;
    assert(lens_distortion.apply(nonfinite[0..], 2, 2, settings(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(lens_distortion.apply(input[0..], 2, 2, settings(),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[11] == 9.0);
}
