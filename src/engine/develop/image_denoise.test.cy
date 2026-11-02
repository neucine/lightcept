import .engine.develop.image_denoise;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn asset(): image_denoise.NoiseAsset {
    return {
        version: 1,
        sigma_y: 0.2,
        sigma_chroma: 0.2,
        strength: 1.0,
        maximum_change: 0.1
    };
}

test "image denoise keeps neutral and disabled images exact" {
    const input: [12]f32 = [0.18] ** 12;
    var output: [12]f32 = [9.0] ** 12;
    assert(image_denoise.apply(input[0..], 2, 2, asset(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[11] == input[11]);
    var disabled = asset();
    disabled.strength = 0.0;
    const colorful: [6]f32 = [-0.1, 0.18, 1.5, 0.2, 0.3, 0.4];
    var unchanged: [6]f32 = [9.0] ** 6;
    assert(image_denoise.apply(colorful[0..], 2, 1, disabled,
        unchanged[0..], no_cancel, 0
    ) == 0);
    assert(unchanged[0] == colorful[0] and unchanged[2] == colorful[2]
        and unchanged[5] == colorful[5]
    );
}

test "bilateral neighborhood reduces small noise while retaining a large edge" {
    const input: [9]f32 = [0.1, 0.1, 0.1, 0.2, 0.2, 0.2,
        1.5, 1.5, 1.5
    ];
    var output: [9]f32 = [9.0] ** 9;
    assert(image_denoise.apply(input[0..], 3, 1, asset(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > 0.1 and output[0] < 0.2);
    assert(output[3] < 0.2 and output[3] > 0.1);
    assert(output[6] > 1.4 and output[6] <= 1.5);
}

test "image denoise bounds change and rejects failures before writing" {
    const input: [3]f32 = [0.1, 0.2, 0.3];
    var output: [3]f32 = [9.0, 9.0, 9.0];
    var invalid = asset();
    invalid.sigma_y = 0.0;
    assert(image_denoise.apply(input[0..], 1, 1, invalid,
        output[0..], no_cancel, 0
    ) == 1);
    assert(image_denoise.apply(input[0..], 2, 1, asset(),
        output[0..], no_cancel, 0
    ) == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const bad: [3]f32 = [infinity, 0.2, 0.3];
    assert(image_denoise.apply(bad[0..], 1, 1, asset(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(image_denoise.apply(input[0..], 1, 1, asset(),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[1] == 9.0 and output[2] == 9.0);
}

test "detail loss cap limits a bright single-pixel feature" {
    var input: [27]f32 = [0.0] ** 27;
    input[12] = 1.0;
    input[13] = 1.0;
    input[14] = 1.0;
    var output: [27]f32 = [9.0] ** 27;
    var settings = asset();
    settings.sigma_y = 0.5;
    settings.maximum_change = 0.01;
    assert(image_denoise.apply(input[0..], 3, 3, settings,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[12] >= 0.99 and output[12] < 1.0);
    assert(output[0] >= 0.0 and output[0] <= 0.01);
}
